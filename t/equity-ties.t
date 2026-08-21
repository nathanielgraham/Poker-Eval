use strict;
use warnings;
use Test::More;
use Poker::Game::Holdem;

# Identical hands on a fixed board must split the pot ~50/50
{
  my $game = Poker::Game::Holdem->new( iterations => 200 );
  my $h1 = $game->deal_hole( [ 'As', 'Kd' ] );
  my $h2 = $game->deal_hole( [ 'Ad', 'Kh' ] );  # same ranks, different suits
  $game->flop( [ '2c', '7d', '9h' ] );
  $game->turn('3s');
  $game->river('8c');
  # Board is dry; both have AK high -- pure chop every time
  $game->equity( [ $h1, $h2 ] );

  is( $h1->ev + $h2->ev, 100, 'chop equities sum to 100' );
  ok( abs( $h1->ev - 50 ) <= 1, 'hand1 ~50 on pure chop' );
  ok( abs( $h2->ev - 50 ) <= 1, 'hand2 ~50 on pure chop' );
}

# Three-way identical high -- each ~33
{
  my $game = Poker::Game::Holdem->new( iterations => 150 );
  my $h1 = $game->deal_hole( [ 'As', 'Kd' ] );
  my $h2 = $game->deal_hole( [ 'Ad', 'Kh' ] );
  my $h3 = $game->deal_hole( [ 'Ac', 'Ks' ] );
  $game->flop( [ '2c', '7d', '9h' ] );
  $game->turn('3s');
  $game->river('8c');
  $game->equity( [ $h1, $h2, $h3 ] );

  my $sum = $h1->ev + $h2->ev + $h3->ev;
  ok( $sum >= 99 && $sum <= 101, 'three-way chop sums ~100' );
  ok( abs( $h1->ev - 33 ) <= 2, 'three-way ~33 each (h1)' );
  ok( abs( $h2->ev - 33 ) <= 2, 'three-way ~33 each (h2)' );
  ok( abs( $h3->ev - 33 ) <= 2, 'three-way ~33 each (h3)' );
}

# AA vs KK preflop: AA should be well ahead, sum ~100
{
  my $game = Poker::Game::Holdem->new( iterations => 500 );
  my $aa = $game->deal_hole( [ 'As', 'Ad' ] );
  my $kk = $game->deal_hole( [ 'Ks', 'Kd' ] );
  $game->equity( [ $aa, $kk ] );

  ok( $aa->ev + $kk->ev >= 99 && $aa->ev + $kk->ev <= 101,
    'AA vs KK sum ~100' );
  ok( $aa->ev > 70, 'AA equity > 70% vs KK' );
  ok( $kk->ev < 30, 'KK equity < 30% vs AA' );
  ok( $aa->ev > $kk->ev, 'AA > KK' );
}

done_testing();
