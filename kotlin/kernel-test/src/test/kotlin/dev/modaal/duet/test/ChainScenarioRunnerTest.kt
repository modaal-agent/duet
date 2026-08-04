// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import dev.modaal.duet.kernel.serialization.CanonicalSumSerializer
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * The chain dialect end-to-end on a minimal two-node duet: a `whenAction` on the
 * emitting node, the `hop` seam (the recorded delegate decoded and mapped the way the
 * parent's shell forwards it, with the previous step marked `linkToNext`), and
 * node-scoped then/thenEffects. Source of this corpus's `chain-ping-pong.fixture.json`
 * — the Kotlin twin of the Swift lane's chain self-gate (same nodes, same steps; the
 * behavioral bytes match the Swift corpus's fixture, the metadata is this file's).
 */
class ChainScenarioRunnerTest {

  @Serializable data class PingState(val sent: Int = 0)

  @Serializable(with = PingActionSerializer::class)
  sealed interface PingAction {
    @Serializable @SerialName("fire") data object Fire : PingAction
  }

  object PingActionSerializer :
    CanonicalSumSerializer<PingAction>(
      "PingAction",
      listOf(case(PingAction.Fire::class, PingAction.Fire.serializer())))

  /** The delegate payload the seam carries (decoded via the hop's delegateSerializer). */
  @Serializable data class PingFired(val count: Int)

  @Serializable(with = PingPayloadSerializer::class)
  sealed interface PingPayload {
    @Serializable
    @SerialName("notifyListener")
    data class NotifyListener(val delegate: PingFired) : PingPayload
  }

  object PingPayloadSerializer :
    CanonicalSumSerializer<PingPayload>(
      "PingPayload",
      listOf(
        case(
          PingPayload.NotifyListener::class,
          PingPayload.NotifyListener.serializer(),
          inline = true)))

  private fun pingReduce(state: PingState, action: PingAction): Reduced<PingState, PingPayload> =
    when (action) {
      PingAction.Fire -> {
        val next = state.copy(sent = state.sent + 1)
        Reduced(next, listOf(Effect.Run(PingPayload.NotifyListener(PingFired(next.sent)))))
      }
    }

  @Serializable data class PongState(val received: Int = 0, val lastCount: Int? = null)

  @Serializable(with = PongActionSerializer::class)
  sealed interface PongAction {
    @Serializable @SerialName("pingFired") data class PingFired(val count: Int) : PongAction
  }

  object PongActionSerializer :
    CanonicalSumSerializer<PongAction>(
      "PongAction",
      listOf(case(PongAction.PingFired::class, PongAction.PingFired.serializer())))

  @Serializable(with = PongPayloadSerializer::class)
  sealed interface PongPayload {
    @Serializable @SerialName("unused") data object Unused : PongPayload
  }

  object PongPayloadSerializer :
    CanonicalSumSerializer<PongPayload>(
      "PongPayload",
      listOf(case(PongPayload.Unused::class, PongPayload.Unused.serializer())))

  private fun pongReduce(state: PongState, action: PongAction): Reduced<PongState, PongPayload> =
    when (action) {
      is PongAction.PingFired ->
        Reduced(state.copy(received = state.received + 1, lastCount = action.count))
    }

  private val ping =
    ChainNode(
      "ping", PingState(), PingState.serializer(), PingActionSerializer, PingPayloadSerializer,
      ::pingReduce)
  private val pong =
    ChainNode(
      "pong", PongState(), PongState.serializer(), PongActionSerializer, PongPayloadSerializer,
      ::pongReduce)

  private fun pingPongChain() =
    chainScenario(
      chain = "ping-pong",
      description =
        "The seam receipt: ping's fired delegate crosses the Hop as pong's pingFired " +
          "action; the emitting step is marked linkToNext in the fixture.",
      source = "kotlin/kernel-test/src/test/kotlin/dev/modaal/duet/test/ChainScenarioRunnerTest.kt",
    ) {
      whenAction(ping, "fire emits the fired delegate", PingAction.Fire)
      thenEffects(ping, "exactly the notifyListener effect") {
        it == effectsOf<PingPayload>(Effect.Run(PingPayload.NotifyListener(PingFired(1))))
      }
      hop(
        "the ping→pong seam", from = ping, to = pong,
        delegateSerializer = PingFired.serializer()) { delegate ->
        PongAction.PingFired(delegate.count)
      }
      then(pong, "the count crossed the seam") { it.lastCount == 1 && it.received == 1 }
      whenAction(ping, "a second fire on the same chain", PingAction.Fire)
      thenEffects(ping, "the second delegate carries the new count") {
        it == effectsOf<PingPayload>(Effect.Run(PingPayload.NotifyListener(PingFired(2))))
      }
    }

  @Test
  fun pingPongChainVerifiesOrRecords() {
    ChainScenarioRunner.verifyOrRecord(pingPongChain())
  }

  @Test
  fun chainFixtureMarksTheEmittingStepLinkToNext() {
    // On a fresh record run the committed file does not exist yet (this lane records
    // compact artifacts the CLI materializes after the test run) — record and read
    // the artifact instead; test order must not matter.
    val committed = File(FixtureRunner.fixturesDirectory(), "chain-ping-pong.fixture.json")
    val artifact =
      File(
        File(FixtureRunner.fixturesDirectory().parentFile, ".runs/record/kotlin"),
        "chain-ping-pong.fixture.json")
    if (!committed.isFile) ChainScenarioRunner.record(pingPongChain())
    val file = if (committed.isFile) committed else artifact
    val steps = FixtureRunner.json.parseToJsonElement(file.readText()).jsonObject
      .getValue("steps").jsonArray
    assertEquals(3, steps.size)
    assertEquals(
      true,
      (steps[0].jsonObject["linkToNext"] as? JsonPrimitive)?.booleanOrNull,
      "the hop's source step is marked")
    assertNull(steps[1].jsonObject["linkToNext"], "the hop's target step is not")
    assertEquals("pong", steps[1].jsonObject.getValue("node").jsonPrimitive.content)
  }

  @Test
  fun twoHandlesSharingAKeyAreAnAuthoringError() {
    // The JVM's erased generics can't fail Swift's box cast, so the registry pins each
    // key to its declaring handle instead — the receipt for that platform asymmetry.
    val impostor =
      ChainNode(
        "ping", PingState(), PingState.serializer(), PingActionSerializer,
        PingPayloadSerializer, ::pingReduce)
    val scenario =
      chainScenario(
        chain = "ping-impostor", description = "impostor handle",
        source = "kotlin/kernel-test/src/test/kotlin/dev/modaal/duet/test/ChainScenarioRunnerTest.kt",
      ) {
        whenAction(ping, "fire", PingAction.Fire)
        whenAction(impostor, "fire again", PingAction.Fire)
      }
    // record: the registry trips on the impostor's when — before anything is written.
    assertFailsWith<IllegalStateException> { ChainScenarioRunner.record(scenario) }
  }
}
