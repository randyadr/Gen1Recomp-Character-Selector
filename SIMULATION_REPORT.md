# Red 3D Player v1.7.1 — Simulation Report

This release was evaluated offline against the supplied 107-bone weighted Red rig before packaging.

## Animation validation
- 12 authored biomechanical running poses per complete stride.
- Catmull-Rom interpolation evaluated at 96 intermediate phase samples.
- Full 5,978-position CPU skin evaluated through the cycle.
- No non-finite weighted positions were detected.
- Stance phase was shortened and recovery/swing timing was expanded to read more like natural running than a marching jog.
- Knee, ankle, and toe timing remain staggered so motion travels down the leg instead of all joints reaching their pose together.
- Arm drive was lowered and elbow/wrist follow-through retained so the hands stay nearer the torso.
- Head motion was reduced slightly while preserving the v1.7 head-bob system.

The goal of v1.7.1 is a relaxed natural run with a clearer support leg, recovery leg, and lower athletic arm pump.
