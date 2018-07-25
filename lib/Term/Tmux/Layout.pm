#
# Copyright (C) 2015,2016,2017,2018 Joelle Maslak
# All Rights Reserved - See License
#

package Term::Tmux::Layout;
use v5.8;

# ABSTRACT: Create tmux layout strings programmatically

use strict;
use warnings;
use autodie;

use Carp;
use Moose;
use namespace::autoclean;

=head1 SYNOPSIS

  my $layout = Term::Tmux::Layout->new();
  my $checksum = $layout->set_layout('abc|def');

=head1 DESCRIPTION

Set tmux pane layouts using via a simpler interface.  See also L<tmuxlayout>
which wraps this module in a command-line script.

=cut

=method set_layout( $definition )

This option sets the layout to the string definition provided. The string
provided must follow the requirements of C<layout()> described elsewhere
in this document.

This command will determine the current tmux window size (using
C<get_window_size()>) and then calls C<layout()> to get the layout string
in proper tmux format.  Finally, it executes tmux to select that layout
as the active layout.

You can only run this method from a tmux window.  C<tmuxlayout> is a thin
wrapper around this function.

=cut

sub set_layout {
    if ( $#_ < 1 ) { confess 'invalid call' }
    my ( $self, @def ) = @_;

    my ( $x, $y ) = $self->get_window_size();
    if ( !defined($y) ) { die "Cannot get the current tmux window size"; }

    $self->hsize($x);
    $self->vsize($y);

    my $layout = $self->layout(@def);
    system( 'tmux', 'select-layout', $layout );
    if ($@) {
        die('Could not set layout');
    }

    return $layout;
}

=method layout ( $layout )

This method takes a "layout" in a text format, and outputs
the proper output.

The layout format consists of a text field of numbers or other
characters, separated by new lines.  Each character reflects a
single pane on the screen, defining its' size in rows and
columns.

Some sample layouts:

  11123
  11124

This would create a layout with 4 panes.  The panes would be
arranged such that pane 1 takes up the entire vertical canvas,
but only 3/5ths of the horizontal canvas.  Pane 2 also takes up
the entire vertical canvas, but only 1/5 of the horizontal
canvas.  Pane 3 and 4 are stacked, taking 1/5 of the horizontal
canvas, evenly splitting the vertical canvas.

Note that some layouts cannot be displayed by tmux.  For example,
the following would be invalid:

  1122
  1134
  5556

Tmux divides the entire screen up either horizontally or vertically.
However, there is no single horizontal or vertical split that would
allow this screen to be divided.

This layout can be passed a single scalar, where the rows are
seperated by pipe characters C<|> or new lines.

If this function is passed an array in the place of the definition,
each element starts its own row.  Each element can also contain pipe
or newlines, and these are also interpreted as row deliminators.

Thus, the following are all valid calls to layout:

  $obj->layout('abc|def|ghi');

  $obj->layout("abc\ndef\nghi");

  $obj->layout('abc', 'def', 'ghi');

  $obj->layout('abc|def', 'ghi');

=cut

sub layout {
    if ( $#_ < 1 ) { confess 'invalid call' }
    my ( $self, @desc ) = @_;

    my @rows = split /[\n|]/, join( '|', @desc );
    my $width = length( $rows[0] );
    foreach (@rows) {
        if ( $width != length($_) ) {
            croak 'All rows must be the same length';
        }
    }

    my $desc = join '|', @desc;

    # Where are my divisions?
    my $hdiv = $self->hsize / ( $width * 1.0 );
    my $vdiv = $self->vsize / ( scalar(@rows) * 1.0 );

    my @v_grid;
    for ( my $i = 0; $i < scalar(@rows); $i++ ) {
        $v_grid[$i] = int( $vdiv * $i + .5 );
    }
    my @h_grid;
    for ( my $i = 0; $i < length( $rows[0] ); $i++ ) {
        $h_grid[$i] = int( $hdiv * $i + .5 );
    }
    push @h_grid, $self->hsize + 1;
    push @v_grid, $self->vsize + 1;

    my %gridstruct = (
        hgrid   => \@h_grid,    # H Start positions for each pane
        vgrid   => \@v_grid,    # V Start positions for each pane
        hparent => 0,           # absolute start x position of enclosing window
        vparent => 0,           # absolute start y position of enclosing window
        hoffset => 0,           # We are drawing division at child relative grid location x
        voffset => 0,           # We are drawing division at child relative location x
        hsize   => $#h_grid,    # Child grid size X
        vsize   => $#v_grid,    # Child grid size Y
        layout  => $desc
    );
    my $result = $self->_divide( \%gridstruct );
    return $self->checksum($result) . ",$result";
}

sub _divide {
    if ( $#_ != 1 ) { confess 'invalid call' }
    my ( $self, $gridstruct ) = @_;

    my (@map) = $self->_make_map( $gridstruct->{layout} );

    # Check 1: Are we done (I.E. only one pane left)?
    my %panes;
    foreach my $r (@map) {
        foreach my $c (@$r) {
            $panes{$c} = 1;
        }
    }

    # Absolute Location, in grid units, of H and V of parent
    my $h_grid_parent_b = $gridstruct->{hparent};
    my $v_grid_parent_b = $gridstruct->{vparent};

    # Absolute Location, in colrow of start of parent division
    my $h_char_parent_b = $gridstruct->{hgrid}->[$h_grid_parent_b];
    my $v_char_parent_b = $gridstruct->{vgrid}->[$v_grid_parent_b];

    # Absolute Grid location of H and V start of this division
    my $h_grid_abs_b = $gridstruct->{hparent} + $gridstruct->{hoffset};
    my $v_grid_abs_b = $gridstruct->{vparent} + $gridstruct->{voffset};

    # Absolute Locations, in grid units, of end+1 of this division
    my $h_grid_abs_n = $h_grid_abs_b + $gridstruct->{hsize};
    my $v_grid_abs_n = $v_grid_abs_b + $gridstruct->{vsize};

    # Absolute Location, in col/row, of start of this division
    my $h_char_abs_b = $gridstruct->{hgrid}->[$h_grid_abs_b];
    my $v_char_abs_b = $gridstruct->{vgrid}->[$v_grid_abs_b];
    # if ($h_char_abs_b > 0) { $h_char_abs_b++; } # Adjust for pane border
    # if ($v_char_abs_b > 0) { $v_char_abs_b++; } # Adjust for pane border

    # Absolute Location, in col/row of end+1 of this division
    my $h_char_abs_n = $gridstruct->{hgrid}->[$h_grid_abs_n];
    my $v_char_abs_n = $gridstruct->{vgrid}->[$v_grid_abs_n];

    # Relative Position (to parent) of start of this division
    my $h_char_rel_b = $h_char_abs_b - $h_char_parent_b;
    my $v_char_rel_b = $v_char_abs_b - $v_char_parent_b;

    # Relative Position (to parent) of next division
    my $h_char_rel_n = $h_char_abs_n - $h_char_parent_b;
    my $v_char_rel_n = $v_char_abs_n - $v_char_parent_b;

    # Division width/height in col/rows
    my $h_size = $h_char_rel_n - $h_char_rel_b;
    my $v_size = $v_char_rel_n - $v_char_rel_b;
    if ( $h_char_abs_b == 0 ) { $h_size--; }
    if ( $v_char_abs_b == 0 ) { $v_size--; }

    my $result = "${h_size}x${v_size},${h_char_abs_b},${v_char_abs_b}";

    if ( scalar( keys %panes ) == 1 ) {
        # We throw in a bogus pane value because it is ignroed anyhow
        return "$result,100";
    }

    # Check 2: Can we do a vertical split?
  NEXTV:
    for ( my $i = 1; $i < scalar( @{ $map[0] } ); $i++ ) {
        for ( my $j = 0; $j < scalar(@map); $j++ ) {
            if ( $map[$j]->[ $i - 1 ] eq $map[$j]->[$i] ) {

                # Can't split here
                next NEXTV;
            }
        }

        # We can split here!

        # TODO: We should check that we aren't allowing things
        # that are 0xY or Xx0
        my (@vfield) = $self->_vsplit_field( $gridstruct->{layout}, $i );

        my %left = (
            hgrid   => $gridstruct->{hgrid},
            vgrid   => $gridstruct->{vgrid},
            hparent => $h_grid_abs_b,
            vparent => $v_grid_abs_b,
            hoffset => 0,
            voffset => 0,
            hsize   => $i,
            vsize   => $gridstruct->{vsize},
            layout  => $vfield[0]
        );
        my %right = (
            hgrid   => $gridstruct->{hgrid},
            vgrid   => $gridstruct->{vgrid},
            hparent => $h_grid_abs_b,
            vparent => $v_grid_abs_b,
            hoffset => $i,
            voffset => 0,
            hsize   => $gridstruct->{hsize} - $i,
            vsize   => $gridstruct->{vsize},
            layout  => $vfield[1]
        );

        $result .= '{' . $self->_divide( \%left ) . ',' . $self->_divide( \%right ) . '}';

        return $result;
    }

    # Check 3: Can we do a horizontal split?
  NEXTH:
    for ( my $j = 1; $j < scalar(@map); $j++ ) {
        for ( my $i = 0; $i < scalar( @{ $map[0] } ); $i++ ) {
            if ( $map[ $j - 1 ]->[$i] eq $map[$j]->[$i] ) {

                # Can't split here
                next NEXTH;
            }
        }

        my (@hfield) = $self->_hsplit_field( $gridstruct->{layout}, $j );

        my %left = (
            hgrid   => $gridstruct->{hgrid},
            vgrid   => $gridstruct->{vgrid},
            hparent => $h_grid_abs_b,
            vparent => $v_grid_abs_b,
            hoffset => 0,
            voffset => 0,
            hsize   => $gridstruct->{hsize},
            vsize   => $j,
            layout  => $hfield[0]
        );
        my %right = (
            hgrid   => $gridstruct->{hgrid},
            vgrid   => $gridstruct->{vgrid},
            hparent => $h_grid_abs_b,
            vparent => $v_grid_abs_b,
            hoffset => 0,
            voffset => $j,
            hsize   => $gridstruct->{hsize},
            vsize   => $gridstruct->{vsize} - $j,
            layout  => $hfield[1]
        );
        # We can split here!

        # TODO: We should check that we aren't allowing things
        # that are 0xY or Xx0

        $result .= '[' . $self->_divide( \%left ) . ',' . $self->_divide( \%right ) . ']';

        return $result;
    }

    die("Can't split");
}

sub _hsplit_field {
    if ( $#_ != 2 ) { confess 'invalid call'; }
    my ( $self, $field, $spos ) = @_;

    my (@map) = $self->_make_map($field);

    my (@split) = ( [], [] );
    for ( my $i = 0; $i < scalar( @{ $map[0] } ); $i++ ) {
        for ( my $j = 0; $j < scalar(@map); $j++ ) {

            # Create the row
            if ( $i == 0 ) {
                $split[0]->[$j] = [];
                $split[1]->[$j] = [];
            }

            if ( $j < $spos ) {

                # First map
                $split[0]->[$j]->[$i] = $map[$j]->[$i];
            } else {

                # Second map
                $split[1]->[ $j - $spos ]->[$i] = $map[$j]->[$i];
            }
        }
    }

    my $field1 = join "\n", map { join '', @$_ } @{ $split[0] };
    my $field2 = join "\n", map { join '', @$_ } @{ $split[1] };

    return ( $field1, $field2 );
}

sub _vsplit_field {
    if ( $#_ != 2 ) { confess 'invalid call'; }
    my ( $self, $field, $spos ) = @_;

    my (@map) = $self->_make_map($field);

    my (@split) = ( [], [] );
    for ( my $i = 0; $i < scalar( @{ $map[0] } ); $i++ ) {
        for ( my $j = 0; $j < scalar(@map); $j++ ) {

            # Create the row
            if ( $i == 0 ) {
                $split[0]->[$j] = [];
                $split[1]->[$j] = [];
            }

            if ( $i < $spos ) {

                # First map
                $split[0]->[$j]->[$i] = $map[$j]->[$i];
            } else {

                # Second map
                $split[1]->[$j]->[ $i - $spos ] = $map[$j]->[$i];
            }
        }
    }

    my $field1 = join "\n", map { join '', @$_ } @{ $split[0] };
    my $field2 = join "\n", map { join '', @$_ } @{ $split[1] };

    return ( $field1, $field2 );
}

sub _make_map {
    if ( $#_ != 1 ) { confess 'invalid call' }
    my ( $self, $field ) = @_;

    if ( !defined($field) ) { confess 'Empty field!' }

    my @map;
    my $rpos = 0;
    foreach my $row ( split /[\n|]/, $field ) {
        my $cpos = 0;
        $map[$rpos] = [];
        foreach my $col ( split //, $row ) {
            $map[$rpos]->[$cpos] = $col;
            $cpos++;
        }
        $rpos++;
    }

    return @map;
}

=method checksum( $str )

This method performs the tmux checksum, as described in the tmux
source code in C<layout_checksum()>.  The input value is the string
without the checksum on the front.  The output is the checksum
value as a string (four hex characters).

=cut

sub checksum {
    if ( $#_ != 1 ) { confess 'invalid call'; }
    my ( $self, $str ) = @_;

    # We silently discard a newline if it appears.
    chomp($str);

    my $csum = 0;
    foreach my $c ( split //, $str ) {
        $csum = ( $csum >> 1 ) + ( ( $csum & 1 ) << 15 ) % 65536;
        $csum += ord($c);
        $csum %= 65536;
    }

    return sprintf( "%04x", $csum );
}

=method get_window_size( )

This method fetches the window size for the currently active tmux
window.  If tmux is not running, it instead returns C<undef>.

=cut

sub get_window_size {
    if ( scalar(@_) != 1 ) { confess 'invalid call' }

    my (@windows) = `tmux list-windows`;
    @windows = grep { /\(active\)$/ } map { chomp; $_ } @windows;

    if ( scalar(@windows) ) {
        my ( $x, $y ) = $windows[0] =~ / \[(\d+)x(\d+)\] /a;
        return ( $x, $y );
    }

    return;
}

=attr hsize

Defines the width of the terminal window (the entire canvas),
with a default of 80.

=cut

has 'hsize' => (
    is      => 'rw',
    isa     => 'Int',
    default => 80
);

=attr vsize

Defines the height of the terminal window tmux canvas (does not
include the status line and command line at the bottom, so this
should be one line smaller than the actual terminal emulator
window size).  This defaults to 24.

=cut

has 'vsize' => (
    is      => 'rw',
    isa     => 'Int',
    default => 24
);

=method new

  my $layout = Term::Tmux::Layout( hsize => 80, vsize => 23 );

Create a new layout class.  Optionally takes named parameters
for the C<hsize> and C<vsize>.

=cut

__PACKAGE__->meta->make_immutable;

1;

=head1 TODO

=over 4

=item * Break out command execution

There probably should be a Term::Tmux::Command module to execute tmux
commands, rather than having the window size commands executed directly
by this module.

=back

=head1 REPOSITORY

L<https://github.com/jmaslak/Term-Tmux-Layout>

=head1 SEE ALSO

See L<tmuxlayout> for a command line utility that wraps this module.

=head1 BUGS

Check the issue tracker at:
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Term-Layout>

=cut
