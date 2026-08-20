package Poker::Game;
use strict;
use warnings FATAL => 'all';
use Moo;
use Poker::Dealer;
use Poker::Hand;

=head1 NAME

Poker::Game - Base class for named poker variants

=head1 VERSION

Version 0.10

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

    # Prefer a concrete subclass:
    use Poker::Game::Holdem;
    my $game = Poker::Game::Holdem->new;

    my $hero = $game->deal_hole(['As', 'Kd']);
    $game->flop(['Ah', '7c', '2d']);
    $game->evaluate($hero);
    say $hero->name;   # e.g. One Pair

=head1 DESCRIPTION

C<Poker::Game> is the product-facing layer over C<Poker::Eval> and
C<Poker::Score>. Subclasses wire hole/board counts and the correct
eval/score engines for a specific variant (Hold'em, Omaha, etc.).

The low-level composition API (C<Poker::Eval::*> + C<Poker::Score::*>)
remains fully supported for custom or experimental variants.

=cut

has 'hole_count' => (
  is      => 'ro',
  default => sub { 2 },
);

has 'board_size' => (
  is      => 'ro',
  default => sub { 5 },
);

has 'iterations' => (
  is      => 'rw',
  default => sub { 1000 },
);

has 'eval_engine' => (
  is       => 'ro',
  required => 1,
  isa      => sub {
    die "eval_engine must be a Poker::Eval"
      unless $_[0]->isa('Poker::Eval');
  },
);

has 'scorer' => (
  is       => 'ro',
  required => 1,
  isa      => sub {
    die "scorer must be a Poker::Score"
      unless $_[0]->isa('Poker::Score');
  },
);

has 'dealer' => (
  is      => 'ro',
  lazy    => 1,
  builder => '_build_dealer',
  isa     => sub {
    die "Not a Poker::Dealer" unless $_[0]->isa('Poker::Dealer');
  },
);

sub _build_dealer {
  my $self = shift;
  # Reuse the eval engine's dealer so deck state stays shared
  return $self->eval_engine->dealer;
}

has 'board' => (
  is      => 'rw',
  default => sub { [] },
  isa     => sub { die "Not an array ref" unless ref( $_[0] ) eq 'ARRAY' },
);

has 'pending_discards' => (
  is      => 'rw',
  default => sub { 0 },
);

has 'pending_draws' => (
  is      => 'rw',
  default => sub { 0 },
);

sub BUILD {
  my $self = shift;
  # Keep eval engine wired to the same scorer and board
  $self->eval_engine->scorer( $self->scorer )
    unless $self->eval_engine->scorer;
  $self->eval_engine->community_cards( $self->board );
  $self->dealer->shuffle_deck;
}

=head1 METHODS

=head2 deal_hole

    my $hand = $game->deal_hole;           # random hole_count cards
    my $hand = $game->deal_hole(2);        # random N cards
    my $hand = $game->deal_hole(['As','Kd']);  # specific cards

Returns a C<Poker::Hand> with those hole cards.

=cut

sub deal_hole {
  my ( $self, $arg ) = @_;
  my $cards;
  if ( ref $arg eq 'ARRAY' ) {
    $cards = $self->deal_cards($arg);
  }
  else {
    my $n = defined $arg ? $arg : $self->hole_count;
    $cards = $self->dealer->deal($n);
  }
  return Poker::Hand->new( cards => $cards );
}

=head2 deal_cards

    my $cards = $game->deal_cards(['As', 'Kd']);

Deal specific cards from the deck (alias-friendly name for the old
C<deal_named> concept).

=cut

sub deal_cards {
  my ( $self, $names ) = @_;
  return $self->dealer->deal_named($names);
}

=head2 board_string

Human-readable community cards.

=cut

sub board_string {
  my $self = shift;
  return join '', map { $_->rank . $_->suit } @{ $self->board };
}

=head2 flop / turn / river

Deal the next street. Pass an array ref of card names for a specific
board, or omit for random cards from the remaining deck.

=cut

sub flop {
  my ( $self, $cards ) = @_;
  die "flop requires an empty board" if @{ $self->board };
  return $self->_deal_street( 3, $cards );
}

sub turn {
  my ( $self, $cards ) = @_;
  die "turn requires exactly 3 board cards"
    unless @{ $self->board } == 3;
  return $self->_deal_street( 1, $cards );
}

sub river {
  my ( $self, $cards ) = @_;
  die "river requires exactly 4 board cards"
    unless @{ $self->board } == 4;
  return $self->_deal_street( 1, $cards );
}

sub _deal_street {
  my ( $self, $count, $specific ) = @_;
  my $new;
  if ( ref $specific eq 'ARRAY' ) {
    die "expected $count cards" unless @$specific == $count;
    $new = $self->deal_cards($specific);
  }
  else {
    $new = $self->dealer->deal($count);
  }
  push @{ $self->board }, @$new;
  $self->eval_engine->community_cards( $self->board );
  return $self->board;
}

=head2 can_runout

True when community cards exist, the board is incomplete, and no
discards/draws are pending.

=cut

sub can_runout {
  my $self = shift;
  return 0 unless $self->board_size > 0;
  return 0 if @{ $self->board } >= $self->board_size;
  return 0 if $self->pending_discards;
  return 0 if $self->pending_draws;
  return 1;
}

=head2 runout

Deal all remaining community cards. Dies if C<can_runout> is false.

=cut

sub runout {
  my ( $self, $specific ) = @_;
  die "runout not legal in current state" unless $self->can_runout;
  my $need = $self->board_size - @{ $self->board };
  if ( ref $specific eq 'ARRAY' ) {
    die "expected $need cards" unless @$specific == $need;
    push @{ $self->board }, @{ $self->deal_cards($specific) };
  }
  else {
    push @{ $self->board }, @{ $self->dealer->deal($need) };
  }
  $self->eval_engine->community_cards( $self->board );
  return $self->board;
}

=head2 evaluate

    my $hand = $game->evaluate($hand_or_cards);

Score the best hand using this game's eval rules and scorer.
Mutates and returns the C<Poker::Hand>.

=cut

sub evaluate {
  my ( $self, $arg ) = @_;
  my $hole =
    ref $arg eq 'ARRAY' ? $arg
    : $arg->isa('Poker::Hand') ? $arg->cards
    : die "evaluate requires a Poker::Hand or array ref of cards";

  $self->eval_engine->community_cards( $self->board );
  my $result = $self->eval_engine->best_hand($hole);

  if ( ref $arg && $arg->isa('Poker::Hand') ) {
    $arg->score( $result->score );
    $arg->name( $result->name );
    $arg->best_combo( $result->best_combo );
    return $arg;
  }
  return $result;
}

=head2 equity

    $game->equity([ $hand1, $hand2, ... ]);

Monte-Carlo equity for the given hands from the current board state.
Sets C<< $hand->ev >> (percentage) on each hand. Alias: C<calc_ev>.

=cut

sub equity {
  my ( $self, $hands ) = @_;
  die "equity requires an array ref of hands"
    unless ref $hands eq 'ARRAY';

  my $engine = $self->eval_engine;
  $engine->community_cards( $self->board );
  $engine->community_remaining(
    $self->board_size - @{ $self->board }
  );
  $engine->hole_remaining(0);  # hole cards already dealt
  $engine->simulations( $self->iterations );

  # Reset win counters
  for my $h (@$hands) {
    $h->wins(0);
    $h->ev(0);
  }

  $engine->calc_ev($hands);
  return $hands;
}

# Backward-compatible alias
sub calc_ev { shift->equity(@_) }

=head2 reset

Shuffle a fresh deck and clear the board.

=cut

sub reset {
  my $self = shift;
  $self->board( [] );
  $self->pending_discards(0);
  $self->pending_draws(0);
  $self->eval_engine->community_cards( [] );
  $self->dealer->shuffle_deck;
  return $self;
}

=head1 AUTHOR

Nathaniel Graham, C<< <ngraham at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2016-2026 Nathaniel Graham.

=cut

1;
