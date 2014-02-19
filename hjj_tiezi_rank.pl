use Data::Dumper;
use Encode::Locale;
use Encode;
use Getopt::Std;
use Tiezi::Robot;
use Template;
use utf8;
use strict;
use warnings;
$| = 1;

my %opt;
getopt( 'bqvnopd', \%opt );
$opt{q} = decode( locale => $opt{q} );
$opt{v} = decode( locale => $opt{v} );
$opt{n} ||= 800;
$opt{b} ||= 36;    #xq
$opt{p} ||= 5;
$opt{d} ||= 0.1;

my $xs = Tiezi::Robot->new(
    site            => 'HJJ',
    type            => $opt{t} || 'html',
    max_process_num => $opt{p},
);

my $res = get_query_analyse( $xs, \%opt );
generate_tiezi_table( $res, $opt{o} );

sub calc_tiezi_rank {
    my ( $r, $tz, %o ) = @_;
    return {} unless ($tz);

    my $floors = $tz->{floors};
    my $n      = scalar(@$floors);
    return {} unless ( $n > 0 and $r->{click} );

    #整楼回复中水贴比例（贴子热度） 0 <= $r_a < 1
    my $m = grep { $_->{word_num} < $o{floor_word_num} } @$floors;
    my $r_a = $m == 0 ? 0.01 : sprintf( "%.2f", $m / $n );
    $r_a = 0.99 if ( $r_a == 1 );

    #长贴点击质量（平均点击热度，惩罚短楼层） $r_b >= 0
    my $ceil_n = int( $n / 300 ) + 1;

    #页数越多，后面的楼层点击量会逐步衰减，用等差数列补一下
    my $ceil_x     = ( 1 + 1 + $o{click_page_delta} * ( $ceil_n - 1 ) ) / 2;
    my $ceil_click = int( $ceil_x * $r->{click} / 1000 ) + 1;

    my $r_b = int( $ceil_click / $ceil_n );

    return {
        floor_num        => $n,
        filter_floor_num => $m,
        rank             => $r_a + $r_b,
    };
}

sub get_query_analyse {
    my ( $xs, $opt ) = @_;
    return unless ( $opt->{q} );

    my $res = $xs->get_query_ref(
        $opt->{v},
        board => $opt->{b},
        query => $opt->{q}
    );

    my $floors = $xs->{browser}->request_urls(
        $res->{tiezis},
        deal_sub => sub {
            my ( $r, $tz ) = @_;
            my $rank_ref =
              calc_tiezi_rank( $r, $tz, 
                  floor_word_num => $opt->{n},
                  click_page_delta => $opt->{d}, 
              );
            return { %$r, %$rank_ref };
        },
        request_sub => sub {
            my ($r) = @_;
            print encode( locale => "\r$r->{url}" );
            return $xs->get_tiezi_ref( $r->{url} );
        },
    );

    my @data = sort { $b->{rank} <=> $a->{rank} }
      grep { $_->{rank} } @$floors;
    my $i = 1;
    $_->{id} = $i++ for @data;

    return \@data;
}

sub generate_tiezi_table {
    my ( $res, $file ) = @_;
    my @fields = qw/id poster title rank floor_num click time_s time_e/;
    my @fields_cn =
      qw/排名 发贴人 标题 评分 总楼数 点击数 发贴时间 最新回复时间/;
    for my $r (@$res) {
        $r->{title} = qq[<a href="$r->{url}">$r->{title}</a>];
        $r = [ @{$r}{@fields} ];
    }

    my $s = qq[
    <head>
    <style type='text/css'>
    body {
    font-family: Calibri,Arial, sans-serif;
    font-size: 90%;
    line-height: 110%;
    }
    p {
    text-indent:2em;
    margin:6px;
    }
    td {
    padding:0.15cm;
    border-width:1px;
    border-color:#4bacc6;
    border-style:solid;
    }
    </style>
    </head>
    <table>
    <tr>
    [% FOREACH r IN fields %]
    <td>[% r %]</td>
    [% END %]
    </tr>
    [% FOREACH f IN floors %]
    <tr>
    [% FOREACH r IN f %]
    <td>[% r %]</td>
    [% END %]
    </tr>
    [% END %]
    </table>
    ];

    my $tt = Template->new();
    $tt->process( \$s, { fields => \@fields_cn, floors => $res },
        $file, { binmode => ':utf8' } )
      || die $tt->error(), "\n";
}
