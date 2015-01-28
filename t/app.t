use v5.14.1;
use Test::More;
use Plack::Test;
use HTTP::Request::Common;

use lib 't';
use AppLoader;
my $app = AppLoader->new( 'itemcount' );

test_psgi $app, sub {
    my $cb = shift;
    my $res = $cb->(GET '/');
    is $res->code, '200', '/';
};

done_testing;
