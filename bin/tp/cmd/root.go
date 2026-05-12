package cmd

import (
	"github.com/spf13/cobra"
)

// NewRootCmd returns a fresh root command. Each call returns an
// independent tree so tests can capture stdout/stderr per invocation
// without sharing state.
func NewRootCmd() *cobra.Command {
	root := &cobra.Command{
		Use:           "tp",
		Short:         "Mark checkboxes in markdown task lists",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(
		newPassCmd(),
		newFailCmd(),
		newPartialCmd(),
		newSkipCmd(),
		newDoneCmd(),
		newUntickCmd(),
	)
	return root
}

// noteVerb returns true if the verb requires -n.
func noteVerb(verb string) bool {
	switch verb {
	case "pass", "fail", "partial", "skip":
		return true
	}
	return false
}
