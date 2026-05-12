// Package mark applies a verb (pass/fail/partial/skip/done/untick) to a
// single checkbox line in a markdown file, identified by ID. It rewrites
// the file atomically.
package mark

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/anutron/tp/internal/lineparse"
)

// Verb identifies the operation to perform on a line.
type Verb int

const (
	VerbPass Verb = iota
	VerbFail
	VerbPartial
	VerbSkip
	VerbDone
	VerbUntick
)

func (v Verb) String() string {
	switch v {
	case VerbPass:
		return "pass"
	case VerbFail:
		return "fail"
	case VerbPartial:
		return "partial"
	case VerbSkip:
		return "skip"
	case VerbDone:
		return "done"
	case VerbUntick:
		return "untick"
	default:
		return "unknown"
	}
}

// ErrAlreadyInState is returned when a no-op is detected (e.g., `done`
// on an already-checked line, `untick` on an already-unchecked line).
var ErrAlreadyInState = errors.New("mark: line already in requested state")

// Mark applies verb to the checkbox line identified by id in the file at
// path. note is required for VerbPass/VerbFail/VerbPartial/VerbSkip and
// must be empty for VerbDone/VerbUntick.
//
// On success the file is rewritten atomically via tmpfile + rename in the
// same directory. ErrAlreadyInState signals a no-op.
func Mark(path, id string, verb Verb, note string) error {
	body, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("mark: read %s: %w", path, err)
	}
	content := string(body)

	line, err := lineparse.Match(content, id)
	if err != nil {
		return err
	}

	// No-op detection.
	switch verb {
	case VerbDone:
		if line.Checked {
			return ErrAlreadyInState
		}
	case VerbUntick:
		if !line.Checked {
			return ErrAlreadyInState
		}
	}

	rewritten, err := rewriteLine(line, verb, note)
	if err != nil {
		return err
	}

	newContent := replaceNthLine(content, line.LineIdx, rewritten)
	return atomicWrite(path, []byte(newContent))
}

// rewriteLine returns the new line text (without trailing ending).
func rewriteLine(line lineparse.Line, verb Verb, note string) (string, error) {
	var box string
	switch verb {
	case VerbSkip:
		// Skip leaves the checkbox unchecked.
		box = " "
	case VerbUntick:
		box = " "
	default:
		// pass/fail/partial/done all check the box.
		box = "x"
	}

	idText := line.ID
	if line.BoldID {
		idText = "**" + line.ID + "**"
	}

	// Drop any existing annotation; build a new one if the verb implies one.
	annotation := ""
	switch verb {
	case VerbPass:
		annotation = " – ✅ " + note
	case VerbFail:
		annotation = " – ❌ " + note
	case VerbPartial:
		annotation = " – 🟡 " + note
	case VerbSkip:
		annotation = " – ⏭ " + note
	case VerbDone, VerbUntick:
		annotation = ""
	}

	desc := strings.TrimRight(line.Description, " ")
	return fmt.Sprintf("%s- [%s] %s %s%s", line.Indent, box, idText, desc, annotation), nil
}

// replaceNthLine returns content with the line at index idx replaced by
// newText. Preserves all original line endings.
func replaceNthLine(content string, idx int, newText string) string {
	// Split into lines preserving endings, swap, rejoin.
	var b strings.Builder
	cur := 0
	lineNo := 0
	for cur < len(content) {
		j := cur
		for j < len(content) && content[j] != '\n' {
			j++
		}
		// Line text is content[cur:j], possibly followed by '\n' at j.
		lineText := content[cur:j]
		ending := ""
		if j < len(content) {
			ending = "\n"
			j++
		}
		if lineNo == idx {
			b.WriteString(newText)
		} else {
			b.WriteString(lineText)
		}
		b.WriteString(ending)
		cur = j
		lineNo++
	}
	return b.String()
}

// atomicWrite writes data to path via tmpfile + same-directory rename.
// On any error before rename, the temp file is removed.
func atomicWrite(path string, data []byte) error {
	dir := filepath.Dir(path)
	base := filepath.Base(path)
	tmpPattern := base + ".tp.*.tmp"
	f, err := os.CreateTemp(dir, tmpPattern)
	if err != nil {
		return fmt.Errorf("mark: create tmp: %w", err)
	}
	tmpPath := f.Name()
	cleanup := func() {
		_ = f.Close()
		_ = os.Remove(tmpPath)
	}
	if _, err := f.Write(data); err != nil {
		cleanup()
		return fmt.Errorf("mark: write tmp: %w", err)
	}
	if err := f.Sync(); err != nil {
		cleanup()
		return fmt.Errorf("mark: fsync tmp: %w", err)
	}
	if err := f.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("mark: close tmp: %w", err)
	}
	if err := os.Rename(tmpPath, path); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("mark: rename tmp: %w", err)
	}
	return nil
}
