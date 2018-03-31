#!/usr/bin/perl
use Data::Dumper;
use Encode::Locale;
use Encode;
use Getopt::Std;
use Novel::Robot;
use Novel::Robot::Parser;
use Novel::Robot::Packer;
use Template;
use utf8;
use strict;
use warnings;
$| = 1;

my %opt;
getopt( 'Bqknodc', \%opt );
$opt{q} = decode( locale => $opt{q} );
$opt{k} = decode( locale => $opt{k} );
$opt{n} ||= 800;
$opt{B} ||= 36;    #xq
$opt{d} ||= 0.1;

my $xs = Novel::Robot->new(
    site            => 'hjj',
    type            => $opt{t} || 'html',
);

my $res = get_query_analyse( $xs, \%opt );
generate_tiezi_table( $res, $opt{o} );
write_tiezi_csv($res, $opt{c}) if($opt{c});

sub calc_tiezi_rank {
    my ( $r, $tz, %o ) = @_;
    return {} unless ($tz);

    my $floors = $tz->{floor_list};

    my $n      = $tz->{floor_num};
    #return {} unless ( $n > 0 and $r->{click} );
    return {} unless ( $n > 0 );

    #整楼回复中水贴比例（贴子热度） 0 <= $r_a < 1
    my $m = grep { $_->{word_num} < $o{floor_word_num} } @$floors;
    my $r_a = $m == 0 ? 0.01 : sprintf( "%.2f", $m / $n );
    $r_a = 0.99 if ( $r_a == 1 );

    #长贴点击质量（平均点击热度，惩罚短楼层） $r_b >= 0
    #my $ceil_n = int( ($n-1) / 300 ) + 1;
    my $ceil_n = int( ($n-1) / 300 );

    #页数越多，后面的楼层点击量会逐步衰减，用等差数列补一下
    #my $ceil_x     = ( 1 + 1 + $o{click_page_delta} * ( $ceil_n - 1 ) ) / 2;
    my $ceil_x     = ( 1 + 1 + $o{click_page_delta} * $ceil_n ) / 2;

    my $ceil_click = int( $ceil_x * $r->{click} / 1000 ) + 1;

    my $r_b = int( $ceil_click / ($ceil_n+1) );

    return {
        floor_num        => $n,
        filter_floor_num => $m,
        hot_rank => $r_a, 

        page_num => $ceil_n, 
        page_click_rank => $r_b, 
        rank             => $r_a + $r_b,
        #rank             => $r_a ,
    };
}

sub write_tiezi_csv {
    my ($floors, $file) = @_;
    my @fields = qw/id writer title floor_num click page_num filter_floor_num hot_rank page_click_rank rank time_s time_e/;
    open my $fh, '>', $file;
    print $fh join(",", @fields),"\n";
    print $fh join(",", @{$_}{@fields}),"\n" for @$floors;
    close $fh;
}


sub get_query_analyse {
    my ( $xs, $opt ) = @_;
    return unless ( $opt->{q} );

    my ($info, $res) = $xs->{parser}->get_query_ref(
        $opt->{k},
        board => $opt->{B},
        query_type => $opt->{q}
    );

    my @rank;
    for my $r (@$res){
        print "$r->{url}\n";
        $r->{click} ||= 0; #hjj 查询最近不显示点击数
        my $x = $xs->{parser}->get_tiezi_ref( $r->{url} , only_poster => 0);
        next unless(@{$x->{floor_list}});
        #print Dumper($x);exit;
        my $rank_ref = calc_tiezi_rank( $r, $x, 
                  floor_word_num => $opt->{n},
                  click_page_delta => $opt->{d}, 
              );
            push @rank,  { %$r, %$rank_ref };
    }

    my @data = sort { $b->{rank} <=> $a->{rank} }
      grep { $_->{rank} } @rank;
    my $i = 1;
    $_->{id} = $i++ for @data;

    return \@data;
}

sub generate_tiezi_table {
    my ( $res, $file ) = @_;
    my @fields = qw/id writer title rank floor_num reply time_s time_e/;
    my @fields_cn =
      qw/排名 发贴人 标题 评分 总楼数 回复数 发贴时间 最新回复时间/;
    for my $r (@$res) {
        next unless($r->{title});
        $r->{title} = qq[<a href="$r->{url}">$r->{title}</a>];
        $r = [ @{$r}{@fields} ];
    }

    my $s = qq[
        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
        <html>

    <head>
        <meta http-equiv="content-type" content="text/html; charset=utf-8">
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
    <body>
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
    </body>
    </html>
    ];

    my $tt = Template->new();
    $tt->process( \$s, { fields => \@fields_cn, floors => $res },
        $file, 
        { binmode => ':utf8' } 
    )
      || die $tt->error(), "\n";
}
