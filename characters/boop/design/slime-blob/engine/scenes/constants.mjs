// Phase 2 art candidates, outside accepted motion V1. CONTINUITY.md is the
// specification; check-scenes.mjs pins these timings and aggregate bounds.
export const sceneConstants=Object.freeze({
  entryMs:240,recoveryMs:480,contactMs:120,cycleMs:Object.freeze([3200,3700,4200]),
  timingJitterMs:40,gainJitter:.10,activityFrequency:12,activityDamping:10,
  activityVelocity:1.2,activityBounds:Object.freeze({lean:.08,squash:.06,forward:.05}),
  propFrequency:10,propDamping:14,propRampMs:200,hostLaneTop:.8,
  poseBounds:Object.freeze([1.25,1.32,1.14,.72]),lifeBounds:Object.freeze([.24,.12,.23])
});
export const implementedStates=Object.freeze(['no_app','asleep','idle','listening','starting','planning','working','terminal',
  'tool_use','searching','analyzing','testing','delegating','helper_return','waiting','needs_you','reply_ready',
  'task_complete','error','stopped','poked','tap_spam','wake_up','gesture','notice']);
