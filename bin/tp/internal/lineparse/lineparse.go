// Package lineparse locates a checkbox line in a markdown document by ID.
//
// It supports two line shapes:
//
//	- [ ] **N.M** Description                — bold-ID test-plan style
//	- [ ] N.M Description                    — plain-ID tasks.md style
//
// Both styles may carry an inline annotation after an en-dash separator:
//
//	- [x] **2.4** Desc – ✅ note
//	- [ ] **4.7** Desc – ⏭ reason
//
// Lines inside fenced code blocks (``` ... ```) are skipped. Mentions of
// IDs in prose are not matched — only lines that begin (after any leading
// whitespace) with `- [ ]` or `- [x]` are considered.
package lineparse

import (
	"errors"
	"fmt"
	"regexp"
	"strings"
)

// Sentinel errors returned by Match.
var (
	ErrNotFound  = errors.New("lineparse: id not found")
	ErrAmbiguous = errors.New("lineparse: id matches more than one line")
)

// AmbiguousError carries the 1-based line numbers of every matching line.
// Use errors.As to retrieve, or errors.Is(err, ErrAmbiguous) to detect.
type AmbiguousError struct {
	ID    string
	Lines []int
}

func (e *AmbiguousError) Error() string {
	return fmt.Sprintf("%s: id %q matches lines %v", ErrAmbiguous.Error(), e.ID, e.Lines)
}
func (e *AmbiguousError) Unwrap() error { return ErrAmbiguous }

// Line describes a parsed checkbox line.
type Line struct {
	LineIdx     int
	LineEnding  string
	Indent      string
	Checked     bool
	BoldID      bool
	ID          string
	Description string
	Annotation  string
}

// Annotation regex: captures " – <emoji> <body>" where emoji is one of the
// four status markers. Greedy on body so it consumes to end of line.
//
// The en-dash is U+2013 (–).
var annotationRe = regexp.MustCompile(`\s+–\s+([✅❌🟡⏭])\s+(.+)$`)

// Bold-ID checkbox pattern. Group 1: indent, 2: checkbox state, 3: ID,
// 4: rest (description + optional annotation).
var boldRe = regexp.MustCompile(`^(\s*)- \[([ xX])\] \*\*([^*]+)\*\*\s+(.+)$`)

// Plain-ID checkbox pattern. Group 1: indent, 2: checkbox state, 3: ID,
// 4: rest (description + optional annotation).
//
// The ID is `\d+(\.\d+)*` — pure dotted-numeric — which is intentionally
// stricter than the bold form (where things like "3.1a" can appear).
var plainRe = regexp.MustCompile(`^(\s*)- \[([ xX])\] (\d+(?:\.\d+)*)\s+(.+)$`)

// Match finds the unique checkbox line matching id within content.
func Match(content, id string) (Line, error) {
	lines := splitLinesPreserveEndings(content)

	type candidate struct {
		line   Line
		lineNo int // 1-based for error messages
	}
	var matches []candidate

	inFence := false
	for i, raw := range lines {
		text := raw.text

		// Track fenced code blocks (``` opening/closing). Naïve: any line
		// whose trimmed prefix begins with ``` toggles the fence.
		if strings.HasPrefix(strings.TrimSpace(text), "```") {
			inFence = !inFence
			continue
		}
		if inFence {
			continue
		}

		// Try bold-ID first (more specific).
		if m := boldRe.FindStringSubmatch(text); m != nil {
			if m[3] == id {
				ln := buildLine(i, raw.ending, m[1], m[2], true, id, m[4])
				matches = append(matches, candidate{ln, i + 1})
			}
			continue
		}
		if m := plainRe.FindStringSubmatch(text); m != nil {
			if m[3] == id {
				ln := buildLine(i, raw.ending, m[1], m[2], false, id, m[4])
				matches = append(matches, candidate{ln, i + 1})
			}
			continue
		}
	}

	switch len(matches) {
	case 0:
		return Line{}, fmt.Errorf("%w: %q", ErrNotFound, id)
	case 1:
		return matches[0].line, nil
	default:
		nums := make([]int, len(matches))
		for i, m := range matches {
			nums[i] = m.lineNo
		}
		return Line{}, &AmbiguousError{ID: id, Lines: nums}
	}
}

func buildLine(idx int, ending, indent, box string, bold bool, id, rest string) Line {
	checked := box == "x" || box == "X"
	desc := rest
	annotation := ""
	if m := annotationRe.FindStringSubmatch(rest); m != nil {
		// rest = "Description – ✅ body" → split by stripping the matched suffix.
		suffix := m[0]
		desc = strings.TrimSuffix(rest, suffix)
		annotation = m[1] + " " + m[2]
	}
	return Line{
		LineIdx:     idx,
		LineEnding:  ending,
		Indent:      indent,
		Checked:     checked,
		BoldID:      bold,
		ID:          id,
		Description: desc,
		Annotation:  annotation,
	}
}

type rawLine struct {
	text   string
	ending string
}

// splitLinesPreserveEndings splits content into lines, preserving the
// original line ending of each line. The final line has an empty ending
// if the file did not terminate with a newline.
func splitLinesPreserveEndings(content string) []rawLine {
	var out []rawLine
	i := 0
	for i < len(content) {
		j := i
		for j < len(content) && content[j] != '\n' {
			j++
		}
		text := content[i:j]
		ending := ""
		if j < len(content) {
			ending = "\n"
			// Promote to \r\n if the line text ends with \r.
			if len(text) > 0 && text[len(text)-1] == '\r' {
				text = text[:len(text)-1]
				ending = "\r\n"
			}
			j++
		}
		out = append(out, rawLine{text: text, ending: ending})
		i = j
	}
	return out
}
