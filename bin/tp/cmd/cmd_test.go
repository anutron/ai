package cmd

import (
	"bytes"
	"strings"
	"testing"
)

// runCmd executes the root command with args and returns (stdout, stderr, err).
func runCmd(args ...string) (string, string, error) {
	root := NewRootCmd()
	var stdout, stderr bytes.Buffer
	root.SetOut(&stdout)
	root.SetErr(&stderr)
	root.SetArgs(args)
	err := root.Execute()
	return stdout.String(), stderr.String(), err
}

func TestCmd_PassRequiresNote(t *testing.T) {
	_, _, err := runCmd("pass", "2.4", "-f", "x.md")
	if err == nil {
		t.Fatalf("err = nil, want error about -n")
	}
	if !strings.Contains(err.Error(), "-n") && !strings.Contains(err.Error(), "note") {
		t.Errorf("err = %v, want it to mention -n / note", err)
	}
}

func TestCmd_FailRequiresNote(t *testing.T) {
	_, _, err := runCmd("fail", "2.4", "-f", "x.md")
	if err == nil {
		t.Fatalf("err = nil, want error about -n")
	}
}

func TestCmd_PartialRequiresNote(t *testing.T) {
	_, _, err := runCmd("partial", "2.4", "-f", "x.md")
	if err == nil {
		t.Fatalf("err = nil, want error about -n")
	}
}

func TestCmd_SkipRequiresNote(t *testing.T) {
	_, _, err := runCmd("skip", "2.4", "-f", "x.md")
	if err == nil {
		t.Fatalf("err = nil, want error about -n")
	}
}

func TestCmd_DoneRejectsNote(t *testing.T) {
	_, _, err := runCmd("done", "1.1", "-f", "x.md", "-n", "extra")
	if err == nil {
		t.Fatalf("err = nil, want error about -n not allowed")
	}
	if !strings.Contains(err.Error(), "not allowed") {
		t.Errorf("err = %v, want it to mention 'not allowed'", err)
	}
}

func TestCmd_UntickRejectsNote(t *testing.T) {
	_, _, err := runCmd("untick", "1.1", "-f", "x.md", "-n", "extra")
	if err == nil {
		t.Fatalf("err = nil, want error about -n not allowed")
	}
}

func TestCmd_AllRequireFile(t *testing.T) {
	verbs := [][]string{
		{"pass", "2.4", "-n", "x"},
		{"fail", "2.4", "-n", "x"},
		{"partial", "2.4", "-n", "x"},
		{"skip", "2.4", "-n", "x"},
		{"done", "1.1"},
		{"untick", "1.1"},
	}
	for _, args := range verbs {
		_, _, err := runCmd(args...)
		if err == nil {
			t.Errorf("%v: err = nil, want error about -f", args)
			continue
		}
		if !strings.Contains(err.Error(), "-f") && !strings.Contains(err.Error(), "file") {
			t.Errorf("%v: err = %v, want it to mention -f/file", args, err)
		}
	}
}
