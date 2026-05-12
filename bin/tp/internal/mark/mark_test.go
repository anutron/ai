package mark

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/anutron/tp/internal/lineparse"
)

// copyFixture copies a testdata file into a temp dir and returns the
// path. Tests mutate the copy, never the original.
func copyFixture(t *testing.T, name string) string {
	t.Helper()
	src := filepath.Join("..", "..", "testdata", name)
	body, err := os.ReadFile(src)
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	dst := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(dst, body, 0o644); err != nil {
		t.Fatalf("write tmp %s: %v", dst, err)
	}
	return dst
}

func readLines(t *testing.T, path string) []string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	return strings.Split(string(b), "\n")
}

func findLine(t *testing.T, path, substr string) string {
	t.Helper()
	for _, line := range readLines(t, path) {
		if strings.Contains(line, substr) {
			return line
		}
	}
	t.Fatalf("no line in %s contains %q", path, substr)
	return ""
}

func TestMark_PassOnBoldID(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.4", VerbPass, "stale session worked"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**2.4**")
	want := "- [x] **2.4** Stale session in browser – ✅ stale session worked"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_PassOnPlainID(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	if err := Mark(p, "1.1", VerbPass, "shipped"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "1.1 Build")
	want := "- [x] 1.1 Build the thing – ✅ shipped"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_PassOverwritesAnnotation(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	// 5.2 currently has a fail annotation. Pass should overwrite.
	if err := Mark(p, "5.2", VerbPass, "actually fine"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**5.2**")
	want := "- [x] **5.2** XFO check – ✅ actually fine"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_FailVariant(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.4", VerbFail, "broke"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**2.4**")
	want := "- [x] **2.4** Stale session in browser – ❌ broke"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_PartialVariant(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.4", VerbPartial, "halfway"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**2.4**")
	want := "- [x] **2.4** Stale session in browser – 🟡 halfway"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_SkipLeavesUnchecked(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.4", VerbSkip, "depends on external"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**2.4**")
	want := "- [ ] **2.4** Stale session in browser – ⏭ depends on external"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_SkipOverwritesExistingSkip(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	// 4.7 already has a skip annotation. Skip again with new reason.
	if err := Mark(p, "4.7", VerbSkip, "new reason"); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**4.7**")
	want := "- [ ] **4.7** SVG upload – ⏭ new reason"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_DoneFlipsCheckbox(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	if err := Mark(p, "1.1", VerbDone, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "1.1 Build")
	want := "- [x] 1.1 Build the thing"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_DoneNoOp(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	before, _ := os.ReadFile(p)
	err := Mark(p, "1.3", VerbDone, "")
	if !errors.Is(err, ErrAlreadyInState) {
		t.Errorf("Mark err = %v, want errors.Is(err, ErrAlreadyInState)", err)
	}
	after, _ := os.ReadFile(p)
	if string(before) != string(after) {
		t.Errorf("file content changed on no-op")
	}
}

func TestMark_UntickFlipsAndStrips(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.5", VerbUntick, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "**2.5**")
	want := "- [ ] **2.5** parseResponse error path"
	if got != want {
		t.Errorf("\n got: %q\nwant: %q", got, want)
	}
}

func TestMark_UntickNoOp(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	before, _ := os.ReadFile(p)
	err := Mark(p, "1.1", VerbUntick, "")
	if !errors.Is(err, ErrAlreadyInState) {
		t.Errorf("Mark err = %v, want errors.Is(err, ErrAlreadyInState)", err)
	}
	after, _ := os.ReadFile(p)
	if string(before) != string(after) {
		t.Errorf("file content changed on no-op")
	}
}

func TestMark_PreservesBoldStyle(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "2.4", VerbDone, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "Stale session")
	if !strings.Contains(got, "**2.4**") {
		t.Errorf("got %q, want bold-ID preserved", got)
	}
}

func TestMark_PreservesPlainStyle(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	if err := Mark(p, "1.1", VerbDone, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "Build the thing")
	if strings.Contains(got, "**1.1**") {
		t.Errorf("got %q, want plain-ID preserved (no bold wrap)", got)
	}
	if !strings.Contains(got, "1.1 Build") {
		t.Errorf("got %q, want plain ID 1.1", got)
	}
}

func TestMark_PreservesIndent(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	if err := Mark(p, "3.1a", VerbDone, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	got := findLine(t, p, "Nested")
	if !strings.HasPrefix(got, "  - [x]") {
		t.Errorf("got %q, want two-space indent preserved", got)
	}
}

func TestMark_NotFoundError(t *testing.T) {
	p := copyFixture(t, "test-plan-fixture.md")
	err := Mark(p, "9.9.9", VerbDone, "")
	if !errors.Is(err, lineparse.ErrNotFound) {
		t.Errorf("err = %v, want errors.Is(err, lineparse.ErrNotFound)", err)
	}
}

func TestMark_AmbiguousError(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "dup.md")
	body := "- [ ] 1.1 First\n- [ ] 1.1 Second\n"
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatalf("write tmp: %v", err)
	}
	err := Mark(p, "1.1", VerbDone, "")
	if !errors.Is(err, lineparse.ErrAmbiguous) {
		t.Errorf("err = %v, want errors.Is(err, lineparse.ErrAmbiguous)", err)
	}
}

func TestMark_AtomicWrite_NoTempLeftover(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	if err := Mark(p, "1.1", VerbDone, ""); err != nil {
		t.Fatalf("Mark err = %v, want nil", err)
	}
	dir := filepath.Dir(p)
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("readdir: %v", err)
	}
	for _, e := range entries {
		if strings.Contains(e.Name(), ".tp.") || strings.HasSuffix(e.Name(), ".tmp") {
			t.Errorf("temp file leftover: %s", e.Name())
		}
	}
}

func TestMark_OriginalUntouchedOnError(t *testing.T) {
	p := copyFixture(t, "tasks-fixture.md")
	before, _ := os.ReadFile(p)
	_ = Mark(p, "9.9.9", VerbDone, "") // not-found error
	after, _ := os.ReadFile(p)
	if string(before) != string(after) {
		t.Errorf("file content changed on error")
	}
}
