// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.test

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import dev.modaal.duet.kernel.serialization.CanonicalSumSerializer

/**
 * The scenario DSL end-to-end, against this repo's own kotlin corpus
 * (`kotlin/parity/fixtures/`): a branched scenario records one fixture per
 * variant (REGEN_FIXTURES=1 re-records; the fixture diff is the review
 * artifact) and verifies byte-exactly on every normal run. Governed by the
 * same corpus rules as a consuming repo.
 */
class ScenarioRunnerTest {

  @Serializable
  data class LampState(val on: Boolean = false, val brightness: Int = 0)

  @Serializable(with = LampActionSerializer::class)
  sealed interface LampAction {
    @Serializable @SerialName("toggle") data object Toggle : LampAction

    @Serializable @SerialName("dim") data class Dim(val to: Int) : LampAction

    @Serializable @SerialName("scheduleOff") data object ScheduleOff : LampAction
  }

  object LampActionSerializer :
    CanonicalSumSerializer<LampAction>(
      "LampAction",
      listOf(
        case(LampAction.Toggle::class, LampAction.Toggle.serializer()),
        case(LampAction.Dim::class, LampAction.Dim.serializer(), inline = true),
        case(LampAction.ScheduleOff::class, LampAction.ScheduleOff.serializer()),
      ))

  @Serializable(with = LampPayloadSerializer::class)
  sealed interface LampPayload {
    @Serializable @SerialName("offTimer") data object OffTimer : LampPayload
  }

  object LampPayloadSerializer :
    CanonicalSumSerializer<LampPayload>(
      "LampPayload",
      listOf(case(LampPayload.OffTimer::class, LampPayload.OffTimer.serializer())))

  private fun reduce(state: LampState, action: LampAction): Reduced<LampState, LampPayload> =
    when (action) {
      LampAction.Toggle -> Reduced(state.copy(on = !state.on))
      is LampAction.Dim -> Reduced(state.copy(brightness = action.to))
      LampAction.ScheduleOff ->
        Reduced(state, listOf(Effect.Run(LampPayload.OffTimer, id = "lamp.off")))
    }

  @Test
  fun branchedScenarioRecordsAndVerifiesPerVariant() {
    val scenario =
      scenario<LampState, LampAction, LampPayload>(
        feature = "lamp",
        description = "lamp toggling with two endings",
        source = "kotlin/kernel-test/src/test/kotlin/dev/modaal/duet/test/ScenarioRunnerTest.kt",
      ) {
        given(LampState())
        whenAction("turn on", LampAction.Toggle)
        then("lamp is on") { it.on }
        branch("dimmed evening") {
          whenAction("dim to 30", LampAction.Dim(30))
          then("brightness set") { it.brightness == 30 }
        }
        branch("timed off") {
          whenAction("schedule off", LampAction.ScheduleOff)
          thenEffects("off timer starts") {
            it == effectsOf<LampPayload>(Effect.Run(LampPayload.OffTimer, id = "lamp.off"))
          }
        }
      }
    ScenarioRunner.verifyOrRecord(
      scenario,
      LampState.serializer(),
      LampActionSerializer,
      LampPayloadSerializer,
      ::reduce)
  }

  @Test
  fun fixtureRunnerReplaysARecordedVariant() {
    // The plain fixture replayer over a scenario-recorded file — the same path a
    // consumer's non-DSL fixture tests use.
    FixtureRunner.run(
      "lamp.dimmed-evening",
      LampState.serializer(),
      LampActionSerializer,
      LampPayloadSerializer,
      ::reduce)
  }

}
