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


=head1 SYNOPSIS

    use Poker::Game::Holdem;
    my $game = Poker::Game::Holdem->new;

    my $hero = $game->deal_hole(['As', 'Kd']);
    $game->flop(['Ah', '7c', '2d']);
    $game->evaluate($hero);
    say $hero->name;

=head1 DESCRIPTION

C<Poker::Game> is the product-facing layer over C<Poker::Eval> and
C<Poker::Score>. Subclasses wire hole/board counts and the correct
eval/score engines for a specific variant.

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

# Max discard/draw rounds (1 for single-draw, 3 for triple-draw)
has 'max_draw_rounds' => (
  is      => 'ro',
  default => sub { 0 },
);

has 'draws_left' => (
  is      => 'rw',
  default => sub { 0 },
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
  $self->eval_engine->scorer( $self->scorer )
    unless $self->eval_engine->scorer;
  $self->eval_engine->community_cards( $self->board );
  $self->draws_left( $self->max_draw_rounds );
  $self->dealer->shuffle_deck;
}

sub _assert_no_pending_actions {
  my $self = shift;
  die "cannot deal board while discards are pending"
    if $self->pending_discards;
  die "cannot deal board while draws are pending"
    if $self->pending_draws;
}

=head1 METHODS

=head2 deal_hole

    my $hand = $game->deal_hole;
    my $hand = $game->deal_hole(['As','Kd']);

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

Deal specific cards from the deck.

=cut

sub deal_cards {
  my ( $self, $names ) = @_;
  return $self->dealer->deal_named($names);
}

=head2 board_string

=cut

sub board_string {
  my $self = shift;
  return join '', map { $_->rank . $_->suit } @{ $self->board };
}

=head2 flop / turn / river

=cut

sub flop {
  my ( $self, $cards ) = @_;
  die "flop requires an empty board" if @{ $self->board };
  return $self->_deal_street( 3, $cards );
}

sub turn {
  my ( $self, $cards ) = @_;
  $self->_assert_no_pending_actions;
  die "turn requires exactly 3 board cards"
    unless @{ $self->board } == 3;
  return $self->_deal_street( 1, $cards );
}

sub river {
  my ( $self, $cards ) = @_;
  $self->_assert_no_pending_actions;
  die "river requires exactly 4 board cards"
    unless @{ $self->board } == 4;
  return $self->_deal_street( 1, $cards );
}

sub _normalize_cards {
  my ( $self, $count, $specific ) = @_;
  return undef unless defined $specific;
  if ( ref $specific eq 'ARRAY' ) {
    return $specific;
  }
  return [$specific];
}

sub _deal_street {
  my ( $self, $count, $specific ) = @_;
  my $cards = $self->_normalize_cards( $count, $specific );
  my $new;
  if ($cards) {
    die "expected $count cards" unless @$cards == $count;
    $new = $self->deal_cards($cards);
  }
  else {
    $new = $self->dealer->deal($count);
  }
  push @{ $self->board }, @$new;
  $self->eval_engine->community_cards( $self->board );
  return $self->board;
}

=head2 can_runout

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

=cut

sub runout {
  my ( $self, $specific ) = @_;
  die "runout not legal in current state" unless $self->can_runout;
  my $need = $self->board_size - @{ $self->board };
  my $cards = $self->_normalize_cards( $need, $specific );
  if ($cards) {
    die "expected $need cards" unless @$cards == $need;
    push @{ $self->board }, @{ $self->deal_cards($cards) };
  }
  else {
    push @{ $self->board }, @{ $self->dealer->deal($need) };
  }
  $self->eval_engine->community_cards( $self->board );
  return $self->board;
}

=head2 discard

    $game->discard($hand, '7c');
    $game->discard($hand, ['7c', '2h']);

Remove one or more hole cards. Sets C<pending_draws> so C<draw> is required
before the next round (for draw games).

=cut

sub discard {
  my ( $self, $hand, $which ) = @_;
  die "discard requires a Poker::Hand"
    unless $hand && $hand->isa('Poker::Hand');
  die "no draws left" if $self->max_draw_rounds && $self->draws_left <= 0;

  my @names =
      ref $which eq 'ARRAY' ? @$which
    : defined $which        ? ($which)
    :                         die "discard requires a card or list";

  my %want = map { $_ => 1 } @names;
  my @keep;
  my @removed;
  for my $card ( @{ $hand->cards } ) {
    my $name = $card->rank . $card->suit;
    if ( $want{$name} ) {
      push @removed, $card;
      delete $want{$name};
    }
    else {
      push @keep, $card;
    }
  }
  die "card(s) not found in hand: " . join( ',', keys %want ) if keys %want;

  $hand->cards( \@keep );
  $self->pending_draws(1) if $self->max_draw_rounds;
  return \@removed;
}

=head2 draw

    $game->draw($hand);             # random refill to hole_count
    $game->draw($hand, ['As','Kd']); # specific replacements

Replace discarded cards up to C<hole_count>. Decrements C<draws_left>.

=cut

sub draw {
  my ( $self, $hand, $specific ) = @_;
  die "draw requires a Poker::Hand"
    unless $hand && $hand->isa('Poker::Hand');
  die "draw not pending" unless $self->pending_draws || !$self->max_draw_rounds;
  die "no draws left" if $self->max_draw_rounds && $self->draws_left <= 0;

  my $need = $self->hole_count - @{ $hand->cards };
  die "hand already has hole_count cards" if $need <= 0;

  my $new;
  if ( defined $specific ) {
    my $cards = $self->_normalize_cards( $need, $specific );
    die "expected $need cards" unless @$cards == $need;
    $new = $self->deal_cards($cards);
  }
  else {
    $new = $self->dealer->deal($need);
  }
  push @{ $hand->cards }, @$new;
  $self->pending_draws(0);
  $self->draws_left( $self->draws_left - 1 ) if $self->max_draw_rounds;
  return $hand;
}

=head2 evaluate

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

=cut

sub equity {
  my ( $self, $hands ) = @_;
  die "equity requires an array ref of hands"
    unless ref $hands eq 'ARRAY';

  my $engine = $self->eval_engine;
  $engine->community_cards( $self->board );
  $engine->community_remaining(
    $self->board_size > 0
    ? $self->board_size - @{ $self->board }
    : 0
  );
  $engine->hole_remaining(0);
  $engine->simulations( $self->iterations );

  for my $h (@$hands) {
    $h->wins(0);
    $h->ev(0);
  }

  $engine->calc_ev($hands);
  return $hands;
}

sub calc_ev { shift->equity(@_) }

=head2 reset

=cut

sub reset {
  my $self = shift;
  $self->board( [] );
  $self->pending_discards(0);
  $self->pending_draws(0);
  $self->draws_left( $self->max_draw_rounds );
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
