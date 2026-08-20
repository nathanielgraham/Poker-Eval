package Poker::Game::Holdem;
use strict;
use warnings FATAL => 'all';
use Moo;
use Poker::Eval::Community;
use Poker::Score::High;

=head1 NAME

Poker::Game::Holdem - Texas Hold'em

=head1 VERSION

Version 0.10

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

    use Poker::Game::Holdem;
    use feature qw(say);

    my $game = Poker::Game::Holdem->new( iterations => 1000 );

    my $hero    = $game->deal_hole(['As', 'Kd']);
    my $villain = $game->deal_hole(['7h', '7c']);

    $game->flop(['Ah', 'Kc', '2d']);
    $game->turn('9s');
    $game->river('3c');

    $game->evaluate($hero);
    $game->evaluate($villain);

    say $hero->name;          # Two Pair
    say $hero->best_combo_flat;

    # Or equity from an earlier street:
    $game->reset;
    $hero    = $game->deal_hole(['As', 'Kd']);
    $villain = $game->deal_hole(['7h', '7c']);
    $game->equity([ $hero, $villain ]);
    say $hero->ev;            # approx preflop equity %

=head1 DESCRIPTION

Texas Hold'em: two hole cards, five community cards. Any combination
of hole and community cards may be used to make the best five-card
hand. Standard highball ranking.

=cut

extends 'Poker::Game';

has '+hole_count' => ( default => sub { 2 } );
has '+board_size' => ( default => sub { 5 } );

has '+scorer' => (
  default => sub { Poker::Score::High->new },
);

has '+eval_engine' => (
  default => sub {
    my $self = shift;
    Poker::Eval::Community->new(
      scorer => $self->scorer,
    );
  },
);

=head1 AUTHOR

Nathaniel Graham, C<< <ngraham at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2016-2026 Nathaniel Graham.

=cut

1;
