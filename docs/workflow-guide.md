# Teaching the Robot: A Workflow Guide

## The Thesis

You don't work with the robot -- you teach the robot.

The same engineering practices that make humans effective make AI agents effective. A junior engineer who receives clear requirements, follows a test-driven process, and gets consistent feedback will outperform a senior engineer who gets vague instructions and no accountability. AI agents are no different.

Rules, skills, and specs are how you encode that discipline. They aren't configuration files -- they're the accumulated wisdom of how you want work to get done. Every time you correct the agent, you have a choice: correct it once, or teach it forever. This system makes "forever" easy.

## The Three Layers

### Rules (CLAUDE.md Snippets) -- "How I want you to work."

Rules are persistent behavioral instructions that shape every interaction. They're the equivalent of team norms, coding standards, and "the way we do things here" -- except they're version-controlled, composable, and portable.

Rules live as **snippets** -- small, focused markdown files that get compiled into CLAUDE.md files that Claude reads at the start of every conversation.

**How it works:**

- `claude-rules/snippets/global/*.md` -- Rules that apply everywhere (formatting, git workflow, interaction style)
- `claude-rules/snippets/project/*.md` -- Rules specific to a single project (tech stack, directory structure, domain knowledge)
- `claude-rules/compile.sh` -- Compiles snippets into dist files, which are symlinked to where Claude reads them

<!-- ILLUSTRATION: File layout diagram — snippets → compile.sh → symlinks → CLAUDE.md. Show global vs project paths, how Claude reads compiled output. Technical, annotated. -->
<!-- Generate with /airon-illustrate, save to docs/images/file-layout.png, then replace this block with: -->
<!-- ![File layout diagram](images/file-layout.png) -->

**Why snippets instead of one big file?**

- **Composable** -- Add or remove behaviors without touching unrelated rules
- **Portable** -- Promote a project rule to global scope with one command (`compile.sh promote`)
- **Reviewable** -- Each snippet is a focused, diffable unit
- **Template variables** -- `compile.sh` substitutes variables like `{{project_root}}` during compilation

**The key insight:** Rules compound. A rule about commit messages + a rule about spec-driven development + a rule about testing = an agent that commits spec-compliant, tested code with good messages on every turn. You don't have to ask for it. It just happens.

### Skills (Reusable Workflows) -- "What I want you to be able to do."

Skills are reusable, invokable workflows that teach the agent complex multi-step processes. If rules are "how to behave," skills are "how to do specific jobs."

Examples:

- **`/improve`** -- Runs the agent's own output through a self-critique loop, then writes recommendations back into the rules and skills that produced the output. The agent literally writes its own manual.
- **`/bugbash`** -- Parallelizes QA across multiple sub-agents, each testing a different surface area, then consolidates findings.
- **`/execute-plan`** -- Takes an approved plan document and executes it step by step, committing after each step, pausing for review at defined gates.
- **`/guard`** -- Watches for regressions by running the test suite after every change and blocking commits on failure.

Skills are markdown files in `.claude/skills/`. They contain natural language instructions that Claude follows when the skill is invoked. No special syntax -- just clear, precise instructions for what to do.

**The key insight:** Skills capture process knowledge that would otherwise live only in your head. "How do I want code reviewed?" becomes a skill. "How do I want bugs triaged?" becomes a skill. The agent gets better at your workflows without you repeating yourself.

### Specs (Contracts) -- "What I want you to build."

Specs are the source of truth for intent. They describe what a feature IS -- not how it's implemented, not what the code looks like, but what it does and why.

**The hierarchy is absolute: Spec > Code.** If the spec and the code disagree, the spec is right and the code has a bug.

Specs live in a `specs/` directory within each project, opted in via a `.specs` file at the project root. The format is simple markdown:

```markdown
# SPEC: Feature Name

## Purpose
Why this exists, what problem it solves

## Interface
- **Inputs**: What goes in
- **Outputs**: What comes out

## Behavior
Given X, the system does Y, resulting in Z

## Test Cases
- Happy path
- Error cases
- Edge cases
```

**The key insight:** The spec is more valuable than the code. Code can be regenerated from a good spec. A spec cannot be reverse-engineered from code -- you lose the "why." Every behavioral change updates the spec on the same turn, keeping the contract and the implementation in sync.

## The Spec/TDD Process

The process is simple and the order is non-negotiable:

<!-- ILLUSTRATION: Spec/TDD cycle — interview → spec → plan → test → implement → review → improve loop. Technical flow diagram. -->
<!-- Generate with /airon-illustrate, save to docs/images/spec-tdd-cycle.png, then replace this block with: -->
<!-- ![Spec/TDD cycle](images/spec-tdd-cycle.png) -->

### 1. Interview

Before writing anything, understand what you're building. This is a conversation -- the agent asks questions, you provide context. The goal is to surface requirements, constraints, and edge cases before any code exists.

### 2. Spec

Write the spec document. This captures the full behavioral contract: what the feature does, what inputs it accepts, what outputs it produces, and how it handles errors. The spec gets reviewed and approved before any code is written.

### 3. Plan

Break the spec into an implementation plan -- ordered steps, each small enough to complete and verify independently. The plan is the most important step. A good plan makes implementation mechanical. A bad plan (or no plan) leads to thrashing, rework, and scope creep.

### 4. Test

Write tests from the spec. The tests encode the spec's behavioral expectations in executable form. At this point, all tests should fail -- you haven't written any implementation yet.

### 5. Implement

Write code to pass the tests. This is the easiest step if the spec and tests are good. The implementation is constrained by the spec (what to build) and validated by the tests (whether it's correct).

### 6. Review

Run the tests. Check the output. Verify against the spec. If something doesn't match, fix the code -- not the spec (unless the spec was wrong, in which case update the spec first, then the tests, then the code).

### 7. Improve

After shipping, run `/improve` to reflect on the process. What rules need updating? What skills could be added? What specs need refinement? The improve step feeds back into the rules and skills layers, making the next cycle better.

## FAQ / Lessons Learned

### "Do you read every line of the skills?"

No. The workflow is: **use, codify, iterate.**

You start by doing things manually in conversation. When you find yourself repeating the same instructions, you write a skill. When the skill produces suboptimal output, you refine it. Most skills start as 10-line drafts and grow to 50-100 lines over a few iterations. You don't need to get it right the first time -- you need to get it written down.

### "How does this work on shared codebases?"

PR feedback becomes skill updates. When a reviewer catches a pattern violation, don't just fix the code -- update the rule or skill that should have prevented it. Over time, the agent learns the team's standards and the same feedback never needs to be given twice.

Send specs, not code reviews. When collaborating on a feature, share the spec document. It's faster to review intent than implementation, and disagreements caught at the spec level are 10x cheaper to resolve than disagreements caught in code review.

### "What about domain knowledge?"

Interview yourself. When you know something the agent doesn't -- business rules, historical context, architectural decisions -- write it down as a rule or include it in the spec. The agent can't read your mind, but it can read your documentation.

Build the dictionary. Domain-specific terms, acronyms, and conventions should live in a rule snippet. "When I say 'sync,' I mean the Fitbit-to-memory pipeline, not git operations." One snippet eliminates an entire class of misunderstandings.

### "Should we spec the whole codebase?"

No. Boil-the-ocean spec projects fail for the same reason boil-the-ocean rewrites fail: they take too long and go stale before they're done.

Instead: **every commit includes spec intent.** When you touch a file, spec the behavior you're changing. After 120 days of active development, you'll have specs covering every actively-maintained surface area. The cold corners that nobody touches don't need specs -- if they're not changing, they're not breaking.

This is the 120-day rule: consistent, incremental spec coverage beats a 2-week documentation sprint every time.

### "What if the agent ignores the rules?"

It happens, especially with complex or contradictory rules. The fix is the same as with humans: make the rules clearer, not more numerous. If a rule isn't being followed:

1. Check if it conflicts with another rule
2. Simplify the language
3. Add a concrete example
4. Move it higher in the compilation order (rules read earlier have more influence)

### "Is this just for Claude Code?"

The principles are universal. Rules, skills, and specs work with any AI coding agent that reads context files. The specific tooling (compile.sh, skill invocation syntax) is Claude Code-specific, but the three-layer model -- behavioral rules, reusable workflows, behavioral contracts -- applies to any agent-assisted development workflow.
