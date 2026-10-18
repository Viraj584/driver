# Demonstration risk model

Scores are policy signals, not probabilities of fraud. The evaluator in `lib/core/risk/risk_engine.dart` is deterministic and intentionally small for reproducible demonstrations.

| Signal | Weight | Reason |
|---|---:|---|
| Device change | 0.30 | `DEVICE_CHANGE` |
| GPS jump with poor accuracy | 0.05 | `GPS_UNCERTAIN` |
| GPS discontinuity with usable accuracy | 0.35 | `GPS_DISCONTINUITY` |
| Unusual speed delta | 0.35 | `IMPLAUSIBLE_SPEED_DELTA` |
| Possible handoff (correlated device/session signals) | 0.65 | `DEVICE_CHANGE`, `INCONSISTENT_SESSION` |
| Successful demonstration check | −0.25, floor 0 | `VERIFICATION_PASSED` |

The combined score is clamped to `[0,1]`. At `0.60`, the demo requests step-up verification. At `0.85`, it marks review required; it never freezes an account based on the score. A failed demonstration check shows a restricted example state, but a real state transition must be authorized and recorded by a backend. Repeated events are not accumulated across sessions in this in-memory demo.

This is not calibrated against real fleet data. Location uncertainty, elapsed time, travel context, connectivity gaps, device replacement explanations, and adversarial input are not modeled. Production decisions require a validated model and documented policy.
