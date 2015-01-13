use v5.14.1;
use Plack::App::WrapCGI;
Plack::App::WrapCGI->new(script => "bin/itemcount.pl", execute => 1)->to_app;
