package Poker::Eval;
use strict;
use Moo;
use Poker::Hand;
use Poker::Dealer;
use Algorithm::Combinatorics qw(combinations);
use Storable qw(dclone);

=head1 NAME

Poker::Eval - Deal, score, and evaluate poker hands

=head1 VERSION

0.10

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

Preferred interface — named games:

    use Poker::Game::Holdem;
    use feature qw(say);

    my $game = Poker::Game::Holdem->new( iterations => 1000 );
    my $hero    = $game->deal_hole(['As', 'Kd']);
    my $villain = $game->deal_hole(['7h', '7c']);

    $game->flop(['Ah', 'Kc', '2d']);
    $game->turn('9s');
    $game->river('3c');

    $game->evaluate($hero);
    say $hero->name;          # Two Pair
    say $hero->best_combo_flat;

    $game->reset;
    $hero    = $game->deal_hole(['As', 'Kd']);
    $villain = $game->deal_hole(['7h', '7c']);
    $game->equity([ $hero, $villain ]);
    say $hero->ev;

Advanced — compose rules and scoring yourself:

    use Poker::Eval::Omaha;
    use Poker::Score::High;

    my $ev = Poker::Eval::Omaha->new(
      scorer => Poker::Score::High->new,
      community_remaining => 2,
    );

=head1 DESCRIPTION

B<Poker::Game::*> modules are the primary API (Hold'em, Omaha, draw,
stud, Badugi, etc.). They wire hole/board counts to the correct
C<Poker::Eval> and C<Poker::Score> engines.

C<Poker::Eval> remains the rules engine base class (how hole and
community cards combine). C<Poker::Score> defines ranking systems
(highball, lowball, Badugi, …).

Only this module defines C<$VERSION> for the distribution; other
packages intentionally omit it so PAUSE indexes a single release.

=head1 SEE ALSO

Poker::Game::Holdem, Poker::Game::Omaha, Poker::Game::FiveCardDraw,
Poker::Game::SevenCardStud, Poker::Game::Badugi, Poker::Score,
Poker::Dealer

=head1 ATTRIBUTES

=head2 community_cards

Array ref of Poker::Card objects representing community cards

=cut

has 'community_cards' => (
  is      => 'rw',
  isa     => sub { die "Not an array ref!" unless ref( $_[0] ) eq 'ARRAY' },
  builder => '_build_community_cards',
);

sub _build_community_cards {
  return [];
}

=head2 scorer

Required attribute that identifies the scoring system. Must be a Poker::Score
object.

=cut

has 'scorer' => (
  is  => 'rw',
  isa => sub { die "Not an Score object!" unless $_[0]->isa('Poker::Score') },
);

=head2 dealer

Standard Poker::Dealer (52-card deck by default; pass joker_count for jokers).

=cut

has 'dealer' => (
  is  => 'rw',
  isa => sub { die "Not a Poker::Dealer" unless $_[0]->isa('Poker::Dealer') },
  builder => '_build_dealer',
);

=head2 simulations

Number of simulations for expected win rate (default 100).

=cut

has 'simulations' => (
  is      => 'rw',
  default => sub { 100 },
);

has 'hole_remaining' => (
  is      => 'rw',
  default => sub { 0 },
);

has 'community_remaining' => (
  is      => 'rw',
  default => sub { 0 },
);

sub _build_dealer {
  return Poker::Dealer->new;
}

=head1 METHODS

=head2 best_hand

Returns the best Poker::Hand for the given hole cards under this eval's rules.

=cut

sub best_hand { }

sub flatten {
  my ( $self, $cards ) = @_;
  return join( '', map { $_->rank . $_->suit } @{$cards} );
}

sub community_flat {
  my $self = shift;
  return $self->flatten( $self->community_cards );
}

sub deal {
  my ( $self, $count ) = @_;
  return $self->dealer->deal($count);
}

sub deal_named {
  my ( $self, $cards ) = @_;
  return $self->dealer->deal_named($cards);
}

=head2 calc_ev

Monte-Carlo expected win rate for an array ref of hands. Prefer
C<Poker::Game>'s C<equity> method for the named-game API.

=cut

sub calc_ev {
  my ( $self, $hands ) = @_;
  my $community_orig = dclone( $self->community_cards );
  for ( 1 .. $self->simulations ) {
    $self->dealer->shuffle_deck;
    if ( $self->community_remaining ) {
      $self->community_cards(
        [ @$community_orig, @{ $self->deal( $self->community_remaining ) } ] );
    }
    for my $hand (@$hands) {
      my $combo =
        [ @{ $hand->cards }, @{ $self->deal( $self->hole_remaining ) } ];

      my $best_hand = $self->best_hand($combo);
      $hand->temp_score( $best_hand->score );
    }

    my @scores =
      map { $_->temp_score } sort { $a->temp_score <=> $b->temp_score } @$hands;
    my $top_score = pop @scores;
    for my $hand (@$hands) {
      $hand->wins( $hand->wins + 1 ) if $hand->temp_score == $top_score;
    }
  }
  my $total_wins = 0;
  for my $hand (@$hands) {
    $total_wins += $hand->wins;
  }
  for my $hand (@$hands) {
    $hand->ev( int( $hand->wins / $total_wins * 100 ) );
  }
}

sub BUILD {
  my $self = shift;
  $self->dealer->shuffle_deck;
}

=head1 AUTHOR

Nathaniel Graham, C<< <ngraham at cpan.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2016-2026 Nathaniel Graham.

=cut

1;
