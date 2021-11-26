use Locale::Po4a::TransTractor qw(process new);
use Locale::Po4a::Common;

package Locale::Po4a::Gdscriptcomments;

use strict;
use warnings;
use 5.006;

require Exporter;

use vars qw(@ISA @EXPORT $AUTOLOAD);
@ISA    = qw(Locale::Po4a::TransTractor);
@EXPORT = qw();

# `$self->initialize()` **is required** for this module to work.
sub initialize { }


# `$self->handleparagraph($pre_paragraph, $paragraph, $paragraph_reference)`
#
# Given a `$paragraph` constructed from comments in a GDScript file, this method
# saves the paragraph in the respective `*.po[t]` files and appends the translation
# in the translated GDScript file for reconstruction.
#
# It handles indentation through `$pre_paragraph` and wraps the comments to `80`
# characters.
sub handleparagraph {
  # Get the input parameters.
  my $self = shift;
  my $pre_paragraph = shift;
  my $paragraph = shift;
  my $paragraph_reference = shift;

  # If we have a valid paragraph.
  if (length($paragraph)) {
    # Take into consideration `$pre_paragraph` when calculating the wrap column value.
    my $wrapcol = 80 - length($pre_paragraph);
    my $translation = $self->translate($paragraph, $paragraph_reference, "", ("wrap" => 1, "wrapcol" => $wrapcol));

    # Append `$pre_paragraph` at the beginning of each line.
    $translation =~ s/^/$pre_paragraph/mg;

    # Push the result to the output GDScript file.
    $self->pushline("$translation\n");
  }
}


sub parse {
  my $self = shift;

  # Keep track of how many commented lines we store in `$paragraph`.
  my $consecutive_comments = 0;
  my ($pre_paragraph, $paragraph, $paragraph_reference) = ("", "", "");

  # Start by grabbing the first line of the input GDScript file.
  my ($line, $line_reference) = $self->shiftline();
  while (defined($line)) {
    # Remove any trailing whitespace, including newlines, using the substitution
    # construct `s///` like in `sed`.
    $line =~ s/\s+$//;

    # We check for comment lines that don't include ANCHOR|END tags.
    if ($line =~ /^(\s*#.+)$/ && !($line =~ /^\s*#+\s*(?:ANCHOR|END).*$/)) {
      # Save the capture group which represents the comment indentation level.
      $pre_paragraph = $1;
      $consecutive_comments++;
      if ($consecutive_comments == 1) {
        # Save the `$line_reference` only on the first comment line.
        # If we have more comment lines after this one we'll instead
        # concatenate it with the previous `$line` to construct `$paragraph`.
        $paragraph_reference = $line_reference;
      }

      # Remove the indentation from `$line`, including the pound and any other
      # whitespace up to the first word.
      $line =~ s/^\s*#+\s*//g;

      # Concatenate `$line` with constructed `$paragraph` we have so far.
      $paragraph .= "$line ";
    } else {
      # If we don't have a match then it's time to save the previously constructed
      # `$paragraph`. We also append the `$line` afterwards.
      $self->handleparagraph($pre_paragraph, $paragraph, $paragraph_reference);
      $self->pushline("$line\n");

      # Reset the variables and prepare for the next set of comments.
      $consecutive_comments = 0;
      $paragraph = "";
    }

    # Grab he next line from the GDScript file.
    ($line, $line_reference) = $self->shiftline();
  }

  # Handle the `$paragraph` one last time at the end of the file.
  $self->handleparagraph($pre_paragraph, $paragraph, $paragraph_reference);
}

# This is the return value of the module and **it's required**.
1;
