package spacelift

import future.keywords.contains
import future.keywords.if

# Pure destroys are denied in production stacks, warned elsewhere.
# Replacements (destroy + recreate) are always a warning, never a hard block.

deny contains reason if {
    is_production
    rc := input.terraform.resource_changes[_]
    is_pure_destroy(rc)
    reason := sprintf("%s would be destroyed in a production stack", [rc.address])
}

warn contains reason if {
    not is_production
    rc := input.terraform.resource_changes[_]
    is_pure_destroy(rc)
    reason := sprintf("%s would be destroyed", [rc.address])
}

warn contains reason if {
    rc := input.terraform.resource_changes[_]
    is_replacement(rc)
    reason := sprintf("%s will be replaced (destroy + recreate)", [rc.address])
}

is_production if {
    input.spacelift.stack.labels[_] == "env:production"
}

is_pure_destroy(rc) if {
    rc.change.actions == ["delete"]
}

is_replacement(rc) if {
    actions := {a | a := rc.change.actions[_]}
    actions == {"delete", "create"}
}
