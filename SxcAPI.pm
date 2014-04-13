use File::Slurp qw(slurp);
package SxcAPI;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw($HOME sxcdb sxcrpc sxcvalidaddr Dumper burp); 

sub Dumper;

use LWP::UserAgent;
use DBI;
use File::Slurp qw(slurp);
use JSON;
use JSON::RPC::Client;

our $HOME="/var/www/";
our $DBPW=slurp("$HOMEetc/dbpw"); chomp $DBPW;

my $ua = LWP::UserAgent->new;
$ua->timeout(10);

my %sxc;
load_sxc_conf();

my $client = new JSON::RPC::Client;

sub load_sxc_conf {
    %sxc=map {split /\s*=\s*/ unless /^\s*#/} split(/\n/,slurp("$HOMEetc/sexcoin.conf"));
}

my @b58 = qw{
      1 2 3 4 5 6 7 8 9
    A B C D E F G H   J K L M N   P Q R S T U V W X Y Z
    a b c d e f g h i j k   m n o p q r s t u v w x y z
};
my %b58 = map { $b58[$_] => $_ } 0 .. 57;

sub service_status {
    my $stat=slurp("$HOMEetc/sxc.status");
    my %r;
    for (split "\n", $stat) {
        chomp;
        next unless /([^:]+):(.*)/;
        $r{$1}=$2;
    }
    return \%r;
}
 
sub unbase58 {
    use integer;
    my @out;
    for my $c ( map { $b58{$_} } shift =~ /./g ) {
        for (my $j = 25; $j--; ) {
            $c += 58 * ($out[$j] // 0);
            $out[$j] = $c % 256;
            $c /= 256;
        }
    }
    return @out;
}

sub sxcnewaddr {
    my $db=sxcdb();
    my $res=sxcrpc({method=>"getnewaddress"});
    return $res;
}
 
sub sxcvalidaddr {
    # does nothing if the address is valid
    # dies otherwise
    
    # return 0 unless $_[0]=~/^L/;
    use Digest::SHA qw(sha256);
    my @byte = unbase58 shift;

    # return 0 unless
    join('', map { chr } @byte[21..24]) eq
    substr sha256(sha256 pack 'H*', @byte[0..20]), 0, 4;

    return 1;
}

sub sxcrpc {
    my $rpcuri = "http://localhost:$sxc{rpcport}/";
    $client->ua->credentials(
        "localhost:$sxc{rpcport}", 'jsonrpc', $sxc{rpcuser} => $sxc{rpcpassword}
    );

    my $res = $client->call( $rpcuri, $_[0] );
    if (!$res) {
        croak $client->status_line;
    }
    if ($res->is_error) {
        croak $res->error_message;
    }
    return $res->result;
}

sub sxcdb {
	return DBI->connect("DBI:Pg:dbname=sxc;host=127.0.0.1", "sxc", $DBPW, {'RaiseError' => 1});
}

sub Dumper {to_json(@_>1?[@_]:$_[0],{allow_nonref=>1,pretty=>1,canonical=>1,allow_blessed=>1});}

sub burp {
    my ($f, $d)=@_;
    open($t, ">$f.tmp") || die $!;
    print $t $d;
    close $t;
    rename("$f.tmp", $f);
}

sub cache_price {
    my ($coin, $cur) = @_;
    my $dat;
    my $tick="$HOMElog/cur";
    mkdir $tick;

    $coin=lc($coin);
    $cur=lc($cur);

    die unless $coin=~/sxc|btc|ltc/;
    die unless $cur=~/btc|usd|eur|rur/;

    $tick="$tick/$coin.$cur";

    if (((stat($tick))[9])<time()-30) {
        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
		my $res=$ua->get("https://www.poloniex.com/exchange/${coin}_$cur");
        if ($res->is_success) {
            $dat=from_json($res->decoded_content());
            $dat=$dat->{ticker};
            open(FILE, ">:encoding(UTF-8)", "$tick.$$");
            print FILE to_json($dat);
            close FILE;
            rename("$tick.$$", $tick);
            return $dat;
        }
    }
    return from_json(slurp($tick));
}

sub cache_ticker {
    my $dat;
    my $tick="$HOMElog/ticker";
    if (((stat($tick))[9])<time()-30) {
    # poor mans ticker...
        my $ua = LWP::UserAgent->new;
        $ua->timeout(10);
        # my $res=$ua->get("https://btc-e.com/api/2/ltc_btc/ticker");
		my $res=$ua->get("https://www.poloniex.com/public?command=returnTicker");
		
        my $btc;
        if ($res->is_success) {
            my $dat=from_json($res->decoded_content());
            $btc=$dat->{ticker}->{sell};
            if ($btc) {
                my $res=$ua->get("https://blockchain.info/ticker");
                if ($res->is_success) {
                    $dat=from_json($res->decoded_content());
                    for (keys(%$dat)) {
                        $dat->{$_}->{"15m"}*=$btc;
                        $dat->{$_}->{"24h"}*=$btc;
                        $dat->{$_}->{buy}*=$btc;
                        $dat->{$_}->{last}*=$btc;
                        $dat->{$_}->{sell}*=$btc;
                    }
                    open(FILE, ">:encoding(UTF-8)", "$tick.$$");
                    print FILE to_json($dat);
                    close FILE;
                    rename("$tick.$$", $tick);
                    return $dat;
                }
            }
        }
    }
    return from_json(slurp($tick,binmode => ':raw'));
}

1;

# vim: noai:ts=4:sw=4

