// Copyright (c) 2026 Modaal.dev
// Licensed under the MIT License. See LICENSE file for details.

package dev.modaal.duet.receipt

import dev.modaal.duet.kernel.Effect
import dev.modaal.duet.kernel.Reduced
import dev.modaal.duet.kernel.serialization.CanonicalSumSerializer
import dev.modaal.duet.replay.ReplayFeature
import dev.modaal.duet.replay.ReplayRegistry
import dev.modaal.duet.replay.ReplaySession
import dev.modaal.duet.replay.BoundaryReplay
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// The receipt feature: the SAME lamp the kotlin corpus records on the JVM host
// lane (kernel-test's ScenarioRunnerTest), here in a framework-shaped
// commonMain so the Swift consumer replays the committed fixtures across the
// SKIE boundary — the FC-spike convergence shape on the productized artifact.

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

fun lampReducer(state: LampState, action: LampAction): Reduced<LampState, LampPayload> =
  when (action) {
    LampAction.Toggle -> Reduced(state.copy(on = !state.on))
    is LampAction.Dim -> Reduced(state.copy(brightness = action.to))
    LampAction.ScheduleOff ->
      Reduced(state, listOf(Effect.Run(LampPayload.OffTimer, id = "lamp.off")))
  }

private val registry =
  ReplayRegistry(
    listOf(
      ReplayFeature.entry(
        "lamp",
        LampState.serializer(),
        LampActionSerializer,
        LampPayloadSerializer,
        ::lampReducer)))

/** The exported boundary surface the Swift consumer drives. */
object LampBoundary {
  fun canonicalize(rawJson: String): String = BoundaryReplay.canonicalize(rawJson)

  fun makeSession(initialStateJson: String): ReplaySession =
    BoundaryReplay.makeSession(registry, "lamp", initialStateJson)
}
