package lineparse

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func loadFixture(t *testing.T) string {
	t.Helper()
	// testdata is at <module-root>/testdata; from this package the relative
	// path is ../../testdata.
	path := filepath.Join("..", "..", "testdata", "test-plan-fixture.md")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	return string(b)
}

func TestMatch_BoldID(t *testing.T) {
	content := loadFixture(t)
	line, err := Match(content, "2.4")
	if err != nil {
		t.Fatalf("Match(2.4) err = %v, want nil", err)
	}
	if !line.BoldID {
		t.Errorf("BoldID = false, want true")
	}
	if line.ID != "2.4" {
		t.Errorf("ID = %q, want %q", line.ID, "2.4")
	}
	if line.Checked {
		t.Errorf("Checked = true, want false")
	}
	if !strings.Contains(line.Description, "Stale session in browser") {
		t.Errorf("Description = %q, want it to contain %q", line.Description, "Stale session in browser")
	}
}

func TestMatch_PlainID(t *testing.T) {
	path := filepath.Join("..", "..", "testdata", "tasks-fixture.md")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read tasks fixture: %v", err)
	}
	line, err := Match(string(b), "1.1")
	if err != nil {
		t.Fatalf("Match(1.1) err = %v, want nil", err)
	}
	if line.BoldID {
		t.Errorf("BoldID = true, want false")
	}
	if line.ID != "1.1" {
		t.Errorf("ID = %q, want %q", line.ID, "1.1")
	}
	if !strings.Contains(line.Description, "Build the thing") {
		t.Errorf("Description = %q, want %q", line.Description, "Build the thing")
	}
}

func TestMatch_PreservesIndent(t *testing.T) {
	content := loadFixture(t)
	line, err := Match(content, "3.1a")
	if err != nil {
		t.Fatalf("Match(3.1a) err = %v, want nil", err)
	}
	if line.Indent != "  " {
		t.Errorf("Indent = %q, want two spaces", line.Indent)
	}
}

func TestMatch_CapturesAnnotation(t *testing.T) {
	content := loadFixture(t)
	line, err := Match(content, "2.5")
	if err != nil {
		t.Fatalf("Match(2.5) err = %v, want nil", err)
	}
	if !strings.Contains(line.Annotation, "stub") {
		t.Errorf("Annotation = %q, want it to contain %q", line.Annotation, "stub")
	}
	if !strings.Contains(line.Annotation, "✅") {
		t.Errorf("Annotation = %q, want it to contain pass emoji", line.Annotation)
	}
}

func TestMatch_NotFound(t *testing.T) {
	content := loadFixture(t)
	_, err := Match(content, "9.9")
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Match(9.9) err = %v, want errors.Is(err, ErrNotFound)", err)
	}
}

func TestMatch_Ambiguous(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "dup.md")
	body := "- [ ] 1.1 First\n- [ ] 1.1 Second\n"
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write tmp: %v", err)
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read tmp: %v", err)
	}
	_, err = Match(string(b), "1.1")
	if !errors.Is(err, ErrAmbiguous) {
		t.Errorf("Match(1.1) err = %v, want errors.Is(err, ErrAmbiguous)", err)
	}
}

func TestMatch_IgnoresProse(t *testing.T) {
	// The fixture contains a prose paragraph mentioning **2.4**. The real
	// **2.4** checkbox should still be the unique match; the prose mention
	// must not cause an ambiguous match.
	content := loadFixture(t)
	line, err := Match(content, "2.4")
	if err != nil {
		t.Fatalf("Match(2.4) err = %v, want nil", err)
	}
	if line.ID != "2.4" {
		t.Errorf("ID = %q, want %q", line.ID, "2.4")
	}
}

func TestMatch_IgnoresCodeBlock(t *testing.T) {
	// The fixture contains a fenced code block with a `- [ ] **9.9** ...`
	// line. That line must not be reachable via Match — id 9.9 should
	// behave as not found.
	content := loadFixture(t)
	_, err := Match(content, "9.9")
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("Match(9.9) err = %v, want errors.Is(err, ErrNotFound) (code-block content must be ignored)", err)
	}
}
