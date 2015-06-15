#!/usr/bin/perl
#################################################################################
#
#################################################################################
use 5.8.0;
use strict;
use warnings;

use Data::Dumper;
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);
use Log::Log4perl;
use Log::Dispatch::FileRotate;
use File::Basename;
use Time::Piece;
use Text::CSV_XS;
use Zabbix::API;

# デフォルト値
my ( $basename, $dir, $ext ) = fileparse( $0, '.pl' );
my $logfile = '/tmp/' . $basename . '.log';

my $server    = '';
my $user      = '';
my $password  = '';
my $host      = '';
my $item_key  = '';
my $time_from = 0;
my $time_till = 0;
my $limit     = 86400;

# サブルーチン定義
sub help;
sub zabbix_loggin;
sub zabbix_item;
sub zabbix_history;

# 引数取得
my %opts = ();
GetOptions(
    \%opts,         'help|h|?', 'server|s=s',  'user|u=s',
    'password|p=s', 'host|z=s', 'itemkey|i=s', 'from|f=s',
    'till|t=s',     'limit|l=s'
) or help;
help if ( defined( $opts{'help'} ) );

# Log設定
my $logconf = "
    log4perl.rootLogger = ALL, FileRotate
    log4perl.appender.FileRotate = Log::Dispatch::FileRotate
    log4perl.appender.FileRotate.filename = $logfile
    log4perl.appender.FileRotate.layout = Log::Log4perl::Layout::PatternLayout
    log4perl.appender.FileRotate.layout.ConversionPattern = %d{yyyy/MM/dd HH:mm:ss.SSS} [%5p] %M() %m%n
    log4perl.appender.FileRotate.mode = append
    log4perl.appender.FileRotate.max = 1
";
Log::Log4perl::init( \$logconf );
my $logger = Log::Log4perl->get_logger();
$logger->info("Start");

# 引数セット
my $tp;
$server   = $opts{'server'}   if ( defined( $opts{'server'} ) );
$user     = $opts{'user'}     if ( defined( $opts{'user'} ) );
$password = $opts{'password'} if ( defined( $opts{'password'} ) );
$host     = $opts{'host'}     if ( defined( $opts{'host'} ) );
$item_key = $opts{'itemkey'}  if ( defined( $opts{'itemkey'} ) );
if ( defined( $opts{'from'} ) ) {
    $tp =
      localtime( Time::Piece->strptime( $opts{'from'}, '%Y-%m-%dT%H:%M:%S' ) );
    $time_from = $tp->epoch;
}
if ( defined( $opts{'till'} ) ) {
    $tp =
      localtime( Time::Piece->strptime( $opts{'till'}, '%Y-%m-%dT%H:%M:%S' ) );
    $time_till = $tp->epoch;
}
else {
    $time_till = time();
}
$limit     = $opts{'limit'} if ( defined( $opts{'limit'} ) );
$limit     = 86400          if ( $limit > 86400 );
$time_from = $time_till     if ( $time_till < $time_from );

# Zabbix APIログイン
my $zabbix = zabbix_login( $server, $user, $password );

# item取得
my $item = zabbix_item( $zabbix, $host, $item_key );

# 指定範囲Historyデータ取得
my $history = zabbix_history( $zabbix, $item, $time_from, $time_till, $limit );

# HistoryデータCSV出力
my $csv = Text::CSV_XS->new( { binary => 1 } );
my @ary;
foreach my $recode (@$history) {
    if ( defined( $recode->{'clock'} ) && defined( $recode->{'value'} ) ) {
        @ary = ();
        push( @ary, localtime( $recode->{'clock'} )->datetime );
        push( @ary, $recode->{'value'} );
        unless ( $csv->combine(@ary) ) {
            $logger->error_die( "" . $csv->error_diag() );
        }
        print $csv->string() . "\n";
    }
    else {
        $logger->warn("Could not get 'clock' or 'value' from the history data");
    }
}

# Historyデータがない場合
if ( @$history == 0 ) {
    $logger->warn("Could not get the history datas");
    print "No data!\n";
}

# ログアウト
$zabbix->logout;
$logger->info("End");

# ヘルプ
sub help {
    print
"Usage: $0 [-h] -s 'http://zabbix-server/zabbix/api_jsonrpc.php' -u user -p password -z host -i itemkey -f time_from -t time_till [-l limit]\n";
    print "\tTime Format: YYYY-MM-DDTHH:MM:SS\n";
    exit(-1);
}

# Zabbix APIログイン
sub zabbix_login {
    my ( $server, $user, $password ) = @_;
    my $zabbix;

    # ログイン処理
    $logger->info("server: $server, user: $user");
    $zabbix = Zabbix::API->new( server => $server, verbosity => 0 );
    eval { $zabbix->login( user => $user, password => $password ) };
    $logger->error_die(
"could not authenticate. server: $server, user: $user, password: $password"
    ) if ($@);

    # APIバージョン情報
    $logger->info( "Zabbix API Version: " . $zabbix->api_version );

    return $zabbix;
}

# Zabbixのitemデータ構造を取得
sub zabbix_item {
    my ( $zabbix, $host, $item_key ) = @_;
    my $item = {};

    $logger->debug("host: $host, item_key: $item_key");
    my $items = $zabbix->query(
        method => 'item.get',
        params => {
            output => 'extend',
            host   => $host,
            filter => { 'key_' => $item_key }
          }

    );
    if ( defined( $items->[0] ) ) {
        $item = $items->[0];
    }
    else {
        $logger->warn(
            "Could not get the item. host: $host, item_key: $item_key");
    }

    return $item;
}

# Zabbixのhistoryデータ構造を取得
sub zabbix_history {
    my ( $zabbix, $item, $time_from, $time_till ) = @_;
    my $history    = [];
    my $itemid     = 0;
    my $value_type = -1;

    $itemid     = $item->{'itemid'}     if ( defined( $item->{'itemid'} ) );
    $value_type = $item->{'value_type'} if ( defined( $item->{'value_type'} ) );
    $logger->debug(
"itemid: $itemid, value_type: $value_type, time_from: $time_from, time_till: $time_till, limit: $limit"
    );

    $history = $zabbix->query(
        method => 'history.get',
        params => {
            output    => 'extend',
            itemids   => $itemid,
            history   => $value_type,
            time_from => $time_from,
            time_till => $time_till,
            limit     => $limit,
            sortfield => 'clock',
            sortorder => 'ASC'

        }
    );

    return $history;
}
