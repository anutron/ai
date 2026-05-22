---
name: software-best-practices
description: Use after completing implementation to validate code quality — checks tests, linting, run scripts, error handling, executes code and iterates until success
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
tags: [spec]
---

# Software Best Practices Skill

You are ensuring code quality best practices for a personal project.

**Standard**: Best practices for a personal project hosted locally (not production deployment)

**Goal**: Enable confident iteration, not enterprise-grade processes

## Your Task

Ensure the project follows essential best practices that enable:
1. Safe iteration without breaking things
2. Clear error messages when things fail
3. Easy testing and validation
4. Maintainability over time

### What to Check

#### 1. Tests Exist and Run

**For Python projects**:
- Look for `test_*.py` or `*_test.py` files
- Check for testing framework (pytest, unittest)
- Try running tests: `pytest` or `python -m unittest`

**For JavaScript/Node projects**:
- Look for `*.test.js` or `*.spec.js` files
- Check for testing framework (jest, mocha)
- Try running tests: `npm test` or `yarn test`

**If no tests**:
- Recommend adding basic tests for core logic
- Suggest starting with happy path
- Provide test template

#### 2. Linting Setup

**For Python**:
- Check for `pyproject.toml`, `setup.cfg`, or `.flake8`
- Look for linting tools (pylint, flake8, black, ruff)
- Try running: `ruff check .` or `flake8 .`

**For JavaScript**:
- Check for `.eslintrc` or `eslint.config.js`
- Look for `prettier` config
- Try running: `npm run lint` or `eslint .`

**If no linting**:
- Not critical for personal projects
- Suggest simple setup if code is complex
- Recommend basic formatter (black, prettier)

#### 3. Run Script Exists

Check for easy way to run the project:

**Python**:
- `run.sh` or `run.py`
- OR clear instructions in README

**JavaScript**:
- `npm start` or `yarn start`
- Scripts in `package.json`

**If missing**:
- Create simple run script
- Document in README

**Example run.sh**:
```bash
#!/bin/bash
set -e

echo "Running workflow project..."

# Activate virtual environment if exists
if [ -d "venv" ]; then
    source venv/bin/activate
fi

# Run the main workflow
python main.py "$@"
```

#### 4. Error Handling

Check for:
- Try/except blocks (Python) or try/catch (JavaScript)
- Meaningful error messages
- Logging to help debug

**Good error handling**:
```python
try:
    result = api_call()
except APIError as e:
    print(f"API call failed: {e}")
    print(f"Retrying with backoff...")
    # Retry logic
```

**Poor error handling**:
```python
try:
    result = api_call()
except:
    pass  # Silent failure
```

#### 5. Code Organization

Check for:
- Clear file structure
- Separated concerns
- Not everything in one giant file

**Good signs**:
- Functions/classes with clear purposes
- Related code grouped together
- Utilities separated from main logic

**Bad signs**:
- Single 1000+ line file
- Functions doing too many things
- No clear organization

### Execution Loop

**This is key**: Don't just check, actually run the code!

1. **Find run command**:
   - Check README for instructions
   - Look for run script
   - Check package.json scripts
   - Look at file structure

2. **Execute the code**:
   ```bash
   # Try to run it
   ./run.sh
   # OR
   python main.py
   # OR
   npm start
   ```

3. **Read output**:
   - Did it work?
   - What errors occurred?
   - Are error messages clear?

4. **Fix issues found**:
   - Missing dependencies? Install them
   - Import errors? Fix imports
   - Logic errors? Fix the bug

5. **Run tests**:
   ```bash
   pytest
   # OR
   npm test
   ```

6. **Read test output**:
   - All passing?
   - What failed?
   - Are failures expected?

7. **Iterate until success**:
   - Fix one issue at a time
   - Re-run after each fix
   - Don't give up after first error

8. **Only involve user if**:
   - Need data/input they must provide
   - Need decision on approach
   - Hit fundamental blocker

### Goal Drift Prevention

**IMPORTANT**: Before spending significant time on fixes, re-evaluate the approach.

**STOP and ask every 20 minutes or after 3 obstacles**:

1. **What was the original goal?**
   - Example: "Connect to service to get data" NOT "Make tests pass"
   - Re-read session/GOAL.md or context.md if it exists

2. **Is this obstacle blocking THE goal or just MY approach?**
   - Blocking goal: "Service API requires auth we don't have"
   - Blocking approach: "Test framework won't install"

3. **How long have I spent on implementation details vs the actual goal?**
   - Red flag: 30+ minutes on test setup when tests aren't the goal
   - Red flag: Adding multiple dependencies for a one-time task
   - Red flag: Debugging framework issues unrelated to core problem

4. **What's the simplest way to achieve the original goal?**
   - Could I call the API manually and copy/paste results?
   - Could I use an existing tool instead of writing code?
   - Could I defer this feature to V2 and do something simpler?

**Examples of goal drift**:
- ❌ Original goal: "Get user data from API"
  - Drift: Now writing unit tests for HTTP client library
  - Recovery: "Can I just use `curl` and save the JSON?"

- ❌ Original goal: "Parse CSV file"
  - Drift: Now building robust ETL pipeline with error handling
  - Recovery: "Can I just read the file with pandas?"

- ❌ Original goal: "Check if service is available"
  - Drift: Now implementing retry logic with exponential backoff
  - Recovery: "Can I just try once and show user the result?"

**Good reasons to continue current approach**:
- ✅ This is the only viable way to achieve the goal
- ✅ Already 80% complete and almost working
- ✅ User explicitly requested this specific implementation
- ✅ Current obstacle is small and directly related to goal

**When to pivot**:
- ⚠️ Spent 20+ minutes on tooling/infrastructure
- ⚠️ Added 3+ dependencies for a simple task
- ⚠️ Building abstractions before proving core concept works
- ⚠️ Current approach more complex than the problem
- ⚠️ User asks "is there an easier way?"

**Pivot strategies**:
1. **Simplify**: Remove abstraction layers, do the minimum
2. **Manual fallback**: Let user do it by hand for V1
3. **Different tool**: Use existing tool instead of writing code
4. **Defer**: Add to IMPROVEMENTS.md, ship without this feature

**Example iteration**:
```
Run 1: ModuleNotFoundError: No module named 'requests'
Fix: pip install requests

Run 2: FileNotFoundError: .env not found
Fix: Create .env.example, update README

Run 3: Success! All tests passing.
```

### Report Findings

**If issues found**:

Write to `project-plan/IMPROVEMENTS.md`:
```markdown
## Code Quality - [Date]

### Tests
- Status: [Missing | Present but failing | Passing]
- Recommendation: [What to add/fix]

### Linting
- Status: [Not configured | Configured]
- Issues: [Number of linting errors, if any]

### Run Script
- Status: [Missing | Present]
- Recommendation: [What to add]

### Error Handling
- Status: [Good | Needs improvement]
- Issues: [Specific cases that need better errors]

### Organization
- Status: [Good | Could improve]
- Recommendations: [Specific refactorings]

### Execution Test
- Result: [Success | Failed]
- Issues found: [What broke]
- Fixes applied: [What was fixed]
- Current status: [Working | Still broken]
```

**If all good**:
```markdown
## Code Quality Check - [Date]
✅ All checks passed

- Tests: Present and passing
- Linting: Configured and clean
- Run script: Works smoothly
- Error handling: Good messages
- Organization: Clear structure
- Execution: Runs successfully
```

### When to Run

This skill is invoked:

1. **During create-agent** when code is generated
2. **During review** if code files exist
3. **Autonomously** when code files created/modified
4. **After fixes** to verify they work

### Not Production Standards

**Don't require**:
- ❌ 100% test coverage
- ❌ CI/CD pipelines
- ❌ Complex build processes
- ❌ Extensive documentation
- ❌ Code review processes
- ❌ Type hints everywhere

**Do require**:
- ✅ Basic tests for core logic
- ✅ Code actually runs
- ✅ Clear error messages
- ✅ Way to test changes easily
- ✅ Basic organization

### Good Enough Bar

**Tests**: Cover the important logic, not every edge case
**Linting**: Optional but helpful for catching obvious issues
**Run script**: One command to run it
**Errors**: Clear enough to debug
**Organization**: Can find code to modify

This is "personal project good", not "ship to customers good".

### Integration with Other Skills

**Called by**:
- `create-agent` when generating code
- `workflow-reviewer` during comprehensive review
- Autonomously when code files modified

**Works with**:
- `save-progress`: Run tests before committing
- `security-checker`: Validate environment setup

## Example Recommendations

### Missing Tests
```markdown
### Recommendation: Add basic tests

Create `test_validator.py`:
```python
def test_query_validation():
    result = validate_query("SELECT * FROM users")
    assert result.valid == True
    assert result.errors == []

def test_query_with_error():
    result = validate_query("SELCT * FROM users")
    assert result.valid == False
    assert "syntax error" in result.errors[0].lower()
```

Run with: `pytest test_validator.py`
```

### Missing Run Script
```markdown
### Recommendation: Add run script

Create `run.sh`:
```bash
#!/bin/bash
set -e

# Check for .env
if [ ! -f ".env" ]; then
    echo "Error: .env file not found"
    echo "Copy .env.example to .env and fill in values"
    exit 1
fi

# Run the workflow
python main.py "$@"
```

Make executable: `chmod +x run.sh`
Run with: `./run.sh`
```

## Key Principles

1. **Actually run the code**: Don't just read, execute
2. **Iterate until it works**: Fix errors one by one
3. **Focus on essentials**: Not everything needs to be perfect
4. **Enable iteration**: User should feel safe making changes
5. **Clear errors**: When it breaks, user knows why

The goal is confident iteration, not perfection.
