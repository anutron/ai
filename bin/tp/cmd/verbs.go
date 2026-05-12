package cmd

import (
	"errors"
	"fmt"

	"github.com/anutron/tp/internal/mark"
	"github.com/spf13/cobra"
)

// noteFlagSet records whether the user actually passed -n on the command
// line. We need to distinguish "not passed" from "passed empty string".
type verbConfig struct {
	verb     mark.Verb
	name     string
	needNote bool // pass/fail/partial/skip
}

func runVerb(cfg verbConfig) func(*cobra.Command, []string) error {
	return func(cmd *cobra.Command, args []string) error {
		file, _ := cmd.Flags().GetString("file")
		note, _ := cmd.Flags().GetString("note")
		noteSet := cmd.Flags().Changed("note")

		if file == "" {
			return errors.New("flag -f/--file is required")
		}
		if cfg.needNote && !noteSet {
			return fmt.Errorf("flag -n/--note is required for %s", cfg.name)
		}
		if !cfg.needNote && noteSet {
			return fmt.Errorf("flag -n/--note is not allowed for %s", cfg.name)
		}
		if len(args) != 1 {
			return errors.New("exactly one positional <id> argument is required")
		}
		id := args[0]

		err := mark.Mark(file, id, cfg.verb, note)
		if errors.Is(err, mark.ErrAlreadyInState) {
			fmt.Fprintf(cmd.ErrOrStderr(), "%s already %s\n", id, alreadyDescription(cfg.verb))
			return nil
		}
		if err != nil {
			return err
		}
		fmt.Fprintf(cmd.OutOrStdout(), "marked %s %s\n", id, cfg.name)
		return nil
	}
}

func alreadyDescription(v mark.Verb) string {
	switch v {
	case mark.VerbDone:
		return "done"
	case mark.VerbUntick:
		return "unchecked"
	default:
		return "in requested state"
	}
}

func newVerbCmd(cfg verbConfig, short string) *cobra.Command {
	c := &cobra.Command{
		Use:   cfg.name + " <id>",
		Short: short,
		Args:  cobra.ExactArgs(1),
		RunE:  runVerb(cfg),
	}
	c.Flags().StringP("file", "f", "", "path to the markdown file (required)")
	if cfg.needNote {
		c.Flags().StringP("note", "n", "", "annotation note (required)")
	} else {
		c.Flags().StringP("note", "n", "", "(not allowed for this verb)")
	}
	return c
}

func newPassCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbPass, name: "pass", needNote: true},
		"Mark a row passing (✅) with a note")
}
func newFailCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbFail, name: "fail", needNote: true},
		"Mark a row failing (❌) with a note")
}
func newPartialCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbPartial, name: "partial", needNote: true},
		"Mark a row partial (🟡) with a note")
}
func newSkipCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbSkip, name: "skip", needNote: true},
		"Mark a row skipped (⏭) with a reason; checkbox stays unchecked")
}
func newDoneCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbDone, name: "done", needNote: false},
		"Flip a checkbox to [x] without an annotation")
}
func newUntickCmd() *cobra.Command {
	return newVerbCmd(verbConfig{verb: mark.VerbUntick, name: "untick", needNote: false},
		"Flip a checkbox to [ ] and strip any annotation")
}
