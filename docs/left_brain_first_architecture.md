# Left-Brain-First Architecture

## Goal

CMYKE should evolve toward a left-brain-first runtime:

- Left brain is the always-on interactive self.
- Right brain is an optional high-cost enhancement service.
- The system must still feel coherent when the right brain is absent.

This is intentionally different from a dual-primary design. The user should feel one continuous agent, not alternating controllers.

## Core Principle

The default operating mode is:

1. Left brain receives the event.
2. Left brain decides whether it can handle it alone.
3. Left brain escalates to the right brain only when the request justifies the cost.
4. Right-brain output returns as support material for the left brain, not as a separate personality takeover.

Three non-negotiable rules:

- Left brain must be able to run on its own.
- Right brain is not part of the default path.
- Right brain can enhance the left brain, but should not replace left-brain authority during live interaction.

## Brain Responsibilities

### Left Brain

The left brain owns low-latency interaction and persistent presence.

Primary responsibilities:

- realtime speech input/output
- visual understanding for immediate interaction
- interruption handling
- short-turn roleplay and emotional continuity
- live reaction to stream, voice channel, and scene events
- lightweight state tracking for "what is happening right now"

The left brain should be optimized for:

- low latency
- stable character expression
- quick recovery after interruption
- continuous presence even when tools or remote APIs are slow

The left brain should not own:

- long multi-step planning
- heavy tool orchestration
- long-form report generation
- deep research loops
- large-scale memory consolidation

### Right Brain

The right brain is a slower cognition service invoked by the left brain.

Primary responsibilities:

- deep reasoning
- multi-step planning
- tool routing and research tasks
- high-quality long-form writing
- memory extraction, restructuring, and consolidation
- note distillation and knowledge shaping

The right brain should be optimized for:

- reasoning quality
- tool use
- structured output quality
- long context handling

The right brain should not be responsible for:

- maintaining the real-time conversational illusion on every turn
- directly owning the live speech loop
- arbitrating every interruption

## Escalation Rules

The left brain should answer alone when the interaction is primarily:

- casual conversation
- roleplay / companionship
- quick voice exchange
- immediate visual reaction
- simple acknowledgements and clarifications
- short emotional or social responses

The left brain should escalate to the right brain when one or more of these are true:

- the user requests analysis, planning, or comparison
- the task needs tools, browsing, or multi-step execution
- the response requires structured long-form output
- the task needs deliberate memory retrieval or note distillation
- the task is too complex to preserve quality under realtime constraints

The preferred interaction pattern is often:

1. Left brain acknowledges immediately.
2. Right brain works in the background if needed.
3. Left brain delivers or stages the result in-character.

This preserves responsiveness without pretending the slow path is instant.

## Shared State Boundary

Both brains should read from the same session-level state surface.

Required shared state:

- active session id
- current role / persona state
- short rolling conversation summary
- currently active user goal
- high-priority core memory summary
- recent event cues (voice, danmaku, visual, tool outcome)
- escalation status (idle / escalating / waiting / reintegrating)

State that should stay minimal for the left brain:

- only the smallest necessary persona and task context
- only top-priority stable memory
- only the most recent live event cues

State that can be expanded for the right brain:

- broader memory retrieval
- notes and archival knowledge
- tool outputs and research traces
- longer planning context

## Memory Injection Strategy

The memory system should not be injected equally into both brains.

Left-brain memory budget:

- stable persona constraints
- current relationship cues
- immediate task / scene state
- a very small set of current-session anchors

Right-brain memory budget:

- core memory
- diary memory
- external knowledge
- note-linked memory
- research artifacts and distilled summaries

The system should prefer:

- left brain = presence and coherence
- right brain = retrieval depth and synthesis

## Current CMYKE Mapping

### Already Close to Left Brain

- `lib/core/services/chat_engine.dart`
  - owns live interaction loop, speech, interruption, voice-channel input, and response path
- `lib/core/services/runtime_event_arbitrator.dart`
  - already models lane priority for voice, moderation, chat, proactive, and danmaku
- `lib/core/services/runtime_hub.dart`
  - central runtime coordination surface for event bus, router, and control
- `lib/features/chat/chat_screen.dart`
  - current shell that hosts the user-facing session flow

### Already Close to Right Brain

- `lib/core/services/control_agent.dart`
  - current decision and dispatch seam for tools and higher-level control
- `lib/core/services/tool_router.dart`
  - remote execution and capability routing surface
- `lib/core/services/universal_agent.dart`
  - general-purpose slower agentic reasoning path
- `lib/core/services/memory_agent.dart`
  - memory extraction / restructuring direction

### Cross-Brain / Shared Infrastructure

- `lib/core/repositories/memory_repository.dart`
  - structured memory storage with distinct tiers
- `lib/core/repositories/note_repository.dart`
  - source material for knowledge shaping and review
- `lib/core/models/app_settings.dart`
  - already separates `llmProviderId`, `realtimeProviderId`, and `omniProviderId`
- `lib/features/settings/provider_config_screen.dart`
  - existing configuration surface, but still route-centric rather than brain-centric

## Architecture Gaps

The current implementation is not yet fully left-brain-first.

Main gaps:

- route selection is still mostly mutually exclusive instead of "left brain + optional right brain"
- `omni` is still treated too much like another route instead of the primary live controller
- fast/slow brain concepts exist in code, but escalation policy is not a first-class contract
- shared state between live interaction and slow cognition is still implicit
- right-brain results can be generated, but reintegration rules are not explicit enough

## Recommended Next Implementation Order

### Phase 1: Brain Contracts

- define `LeftBrainConfig` and `RightBrainConfig`
- define escalation policy and explicit trigger classes
- stop modeling architecture only as `standard / realtime / omni` route switching

### Phase 2: Brain Router

- add a first-class router that decides:
  - left brain only
  - left brain with background right-brain assist
  - direct right-brain escalation for non-live tasks
- record escalation reason in runtime state

### Phase 3: Shared State Surface

- introduce a compact shared session state object for persona, task, and live context
- define what the left brain sees vs what the right brain can expand

### Phase 4: Reintegration Rules

- define how right-brain output returns to the left brain
- enforce that the left brain remains the final live presenter during realtime sessions

### Phase 5: Settings and UX

- reshape settings from route-centric to brain-centric
- expose left-brain model, right-brain model, and escalation policy separately

## Product Interpretation

This architecture supports the intended long-term direction:

- a continuously present interactive self
- strong realtime multimodal exchange
- optional deep cognition when complexity justifies it
- better roleplay continuity than a system that constantly swaps controllers

In short:

- left brain is the character
- right brain is the strategist
- runtime coordination protects the illusion that they are one being
