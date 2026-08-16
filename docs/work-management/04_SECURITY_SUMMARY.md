# Security Summary

All Work tables use RLS. Core state tables deny unrestricted client writes and are changed through authorised RPCs.

Permissions distinguish own, team, branch, all and sensitive visibility. `read_team` never means the entire branch; team scope comes from real hierarchy/queue membership. Branch-wide access is separate.

Mentioning a user never grants access. A Work link never grants permission to the linked HR/Finance/Sales record. Sensitive Work supports restricted/private visibility.