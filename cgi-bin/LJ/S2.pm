#!/usr/bin/perl
#

use strict;
use lib "$ENV{'LJHOME'}/src/s2";
use S2;
use S2::Checker;
use S2::Compiler;
use Storable;
use Apache::Constants ();
use HTMLCleaner;

package LJ::S2;

sub make_journal
{
    my ($u, $styleid, $view, $remote, $opts) = @_;

    my $r = $opts->{'r'};
    my $ret;
    $LJ::S2::ret_ref = \$ret;

    my $ctx = s2_context($r, $styleid);
    unless ($ctx) {
        $opts->{'handler_return'} = Apache::Constants::OK();
        return;
    }
    
    $opts->{'ctx'} = $ctx;

    $ctx->[S2::PROPS]->{'SITEROOT'} = $LJ::SITEROOT;
    $ctx->[S2::PROPS]->{'SITENAME'} = $LJ::SITENAME;
    $ctx->[S2::PROPS]->{'IMGDIR'} = $LJ::IMGPREFIX;
    foreach ("name", "url", "urlname") { LJ::text_out(\$u->{$_}); }

    my ($entry, $page);
    if ($view eq "lastn") {
        $entry = "RecentPage::print()";
        $page = RecentPage($u, $remote, $opts);
    }

    my $run_opts = {
        'content_type' => 'text/html',
    };
    s2_run($r, $ctx, $run_opts, $entry, $page);
    return $ret;
}

sub s2_run
{
    my ($r, $ctx, $opts, $entry, $page) = @_;

    my $ctype = $opts->{'content_type'} || "text/html";
    my $cleaner;
    if ($ctype =~ m!^text/html!) {
        $cleaner = new HTMLCleaner ('output' => sub { $$LJ::S2::ret_ref .= $_[0]; });
    }

    my $send_header = sub {
        my $status = $ctx->[S2::SCRATCH]->{'status'} || 200;
        $r->status($status);
        $r->content_type($ctx->[S2::SCRATCH]->{'ctype'} || $ctype);
        $r->send_http_header();
    };
    
    my $out_straight = sub { $$LJ::S2::ret_ref .= $_[0]; };
    my $out_clean = sub { $cleaner->parse($_[0]); };

    S2::set_output($out_straight);
    S2::set_output_safe($out_straight);

    if ($cleaner) {
        S2::set_output_safe($out_clean);
    }
          
    $LJ::S2::CURR_PAGE = $page;
    $LJ::S2::RES_MADE = 0;  # standard resources (Image objects) made yet

    eval {
        S2::run_code($ctx, $entry, $page);
    };
    if ($@) { 
        my $error = $@;
        $error =~ s/\n/<br>\n/g;
        S2::pout("<b>Error running style:</b> $error");
        return 0;
    }
    S2::pout(undef);  # send the HTTP header, if it hasn't been already
    $cleaner->eof if $cleaner;  # flush any remaining text/tag not yet spit out
    return 1;    
}

# find existing re-distributed layers that are in the database
# and their styleids.
sub get_public_layers
{
    my $sysid = shift;  # optional system userid (usually not used)
    return $LJ::CACHED_PUBLIC_LAYERS if $LJ::CACHED_PUBLIC_LAYERS;

    my $dbr = LJ::get_db_reader();
    $sysid ||= LJ::get_userid($dbr, "system");

    my %existing;  # uniq -> id
    my $sth = $dbr->prepare("SELECT i.value, l.s2lid, l.b2lid, l.type FROM s2layers l, s2info i ".
                            "WHERE l.userid=$sysid AND l.s2lid=i.s2lid AND i.infokey='redist_uniq'");
    $sth->execute;
    die $dbr->errstr if $dbr->err;
    while (my ($uniq, $id, $bid, $type) = $sth->fetchrow_array) {
        $existing{$uniq} = $existing{$id} = {
            's2lid' => $id,
            'b2lid' => $bid,
            'type' => $type,
            'uniq' => $uniq,
        };
        next unless $bid;
        push @{$existing{$bid}->{'children'}}, $id;
    }

    return \%existing if $LJ::LESS_CACHING;
    $LJ::CACHED_PUBLIC_LAYERS = \%existing if %existing;
    return $LJ::CACHED_PUBLIC_LAYERS;
}

sub s2_context
{
    my $r = shift;
    my $styleid = shift;
    my $opts = shift;

    my $dbr = LJ::get_db_reader();

    my %style;
    my $have_style = 0;
    if ($styleid) {
        my $sth = $dbr->prepare("SELECT type, s2lid FROM s2stylelayers ".
                                "WHERE styleid=?");
        $sth->execute($styleid);
        while (my ($t, $id) = $sth->fetchrow_array) { $style{$t} = $id; }
        $have_style = scalar %style;
    }

    unless ($have_style) {
        my $public = get_public_layers();
        while (my ($layer, $name) = each %$LJ::DEFAULT_STYLE) {
            next unless $name ne "";
            next unless $public->{$name};
            my $id = $public->{$name}->{'s2lid'};
            $style{$layer} = $id if $id;
        }
    }

    my @layers;
    foreach (qw(core i18nc layout i18n theme user)) {
        push @layers, $style{$_} if $style{$_};
    }

    my $modtime = S2::load_layers_from_db($dbr, @layers);

    # check that all critical layers loaded okay from the database, otherwise
    # fall back to default style.  if i18n/theme/user were deleted, just proceed.
    my $okay = 1;
    foreach (qw(core layout)) {
        next unless $style{$_};
        $okay = 0 unless S2::layer_loaded($style{$_});
    }
    unless ($okay) {
        # load the default style instead.
        if ($have_style) { return s2_context($r, 0, $opts); }
        
        # were we trying to load the default style?
        $r->content_type("text/html");
        $r->send_http_header();
        $r->print("<b>Error preparing to run:</b> One or more layers required to load the stock style have been deleted.");
        return undef;
    }

    if ($opts->{'use_modtime'})
    {
        my $ims = $r->header_in("If-Modified-Since");
        my $ourtime = LJ::date_unix_to_http($opts->{'modtime'});
        if ($ims eq $ourtime) {
            $r->status_line("304 Not Modified");
            $r->send_http_header();
            return undef;
        } else {
            $r->header_out("Last-Modified", $ourtime);
        }
    }

    my $ctx;
    eval {
        $ctx = S2::make_context(@layers);
    };

    if ($ctx) {
        S2::set_output(sub {});  # printing suppressed
        S2::set_output_safe(sub {}); 
        eval { S2::run_code($ctx, "prop_init()"); };
        return $ctx unless $@;
    }

    my $err = $@;
    $r->content_type("text/html");
    $r->send_http_header();
    $r->print("<b>Error preparing to run:</b> $err");
    return undef;

}

sub clone_layer
{
    my $id = shift;
    return 0 unless $id;

    my $dbh = LJ::get_db_writer();
    my $r;

    $r = $dbh->selectrow_hashref("SELECT * FROM s2layers WHERE s2lid=?", undef, $id);
    return 0 unless $r;
    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) VALUES (?,?,?)",
             undef, $r->{'b2lid'}, $r->{'userid'}, $r->{'type'});
    my $newid = $dbh->{'mysql_insertid'};
    return 0 unless $newid;
    
    foreach my $t (qw(s2compiled s2info s2source)) {
        $r = $dbh->selectrow_hashref("SELECT * FROM $t WHERE s2lid=?", undef, $id);
        next unless $r;
        $r->{'s2lid'} = $newid;

        # kinda hacky:  we have to update the layer id
        if ($t eq "s2compiled") {
            $r->{'compdata'} =~ s/\$_LID = (\d+)/\$_LID = $newid/;
        }

        $dbh->do("INSERT INTO $t (" . join(',', keys %$r) . ") VALUES (".
                 join(',', map { $dbh->quote($_) } values %$r) . ")");
    }

    return $newid;
}

sub create_style
{
    my ($u, $name, $cloneid) = @_;
    
    my $dbh = LJ::get_db_writer();
    my $clone;
    $clone = load_style($cloneid) if $cloneid;

    # can't clone somebody else's style
    return 0 if $clone && $clone->{'userid'} != $u->{'userid'};
    
    # can't create name-less style
    return 0 unless $name =~ /\S/;

    $dbh->do("INSERT INTO s2styles (userid, name) VALUES (?,?)", undef,
             $u->{'userid'}, $name);
    my $styleid = $dbh->{'mysql_insertid'};
    return 0 unless $styleid;

    if ($clone) {
        $clone->{'layer'}->{'user'} = 
            LJ::clone_layer($clone->{'layer'}->{'user'});
        
        my $values;
        foreach my $ly ('core','i18nc','layout','theme','i18n','user') {
            next unless $clone->{'layer'}->{$ly};
            $values .= "," if $values;
            $values .= "($styleid, '$ly', $clone->{'layer'}->{$ly})";
        }
        $dbh->do("REPLACE INTO s2stylelayers (styleid, type, s2lid) ".
                 "VALUES $values") if $values;
    }

    return $styleid;
}

sub load_user_styles
{
    my $u = shift;
    my $opts = shift;
    return undef unless $u;

    my $dbr = LJ::get_db_reader();

    my %styles;
    my $load_using = sub {
        my $db = shift;
        my $sth = $db->prepare("SELECT styleid, name FROM s2styles WHERE userid=?");
        $sth->execute($u->{'userid'});
        while (my ($id, $name) = $sth->fetchrow_array) {
            $styles{$id} = $name;
        }
    };
    $load_using->($dbr);
    return \%styles if scalar(%styles) || ! $opts->{'create_default'};

    # create a new default one for them, but first check to see if they
    # have one on the master.
    my $dbh = LJ::get_db_writer();
    $load_using->($dbh);
    return \%styles if %styles;

    $dbh->do("INSERT INTO s2styles (userid, name) VALUES (?,?)", undef,
             $u->{'userid'}, $u->{'user'});
    my $styleid = $dbh->{'mysql_insertid'};
    return { $styleid => $u->{'user'} };
}

sub delete_user_style
{
    my ($u, $styleid) = @_;
    return 1 unless $styleid;
    my $dbh = LJ::get_db_writer();

    my $style = load_style($dbh, $styleid);
    delete_layer($style->{'layer'}->{'user'});

    foreach my $t (qw(s2styles s2stylelayers)) {
        $dbh->do("DELETE FROM $t WHERE styleid=?", undef, $styleid)
    }

    # TODO: update any of their galleries using it, perhaps.
    return 1;
}

sub load_style
{
    my $db = ref $_[0] ? shift : undef;
    my $id = shift;
    return undef unless $id;

    $db ||= LJ::get_db_reader();
    my $style = $db->selectrow_hashref("SELECT styleid, userid, name ".
                                       "FROM s2styles WHERE styleid=?",
                                       undef, $id);
    return undef unless $style;

    $style->{'layer'} = {};
    my $sth = $db->prepare("SELECT type, s2lid FROM s2stylelayers ".
                           "WHERE styleid=?");
    $sth->execute($id);
    while (my ($type, $s2lid) = $sth->fetchrow_array) {
        $style->{'layer'}->{$type} = $s2lid;
    }
    return $style;
}

sub create_layer
{
    my ($userid, $b2lid, $type) = @_;
    $userid = want_userid($userid);

    return 0 unless $b2lid;  # caller should ensure b2lid exists and is of right type
    return 0 unless 
        $type eq "user" || $type eq "i18n" || $type eq "theme" || 
        $type eq "layout" || $type eq "i18nc" || $type eq "core";

    my $dbh = LJ::get_db_writer();
    return 0 unless $dbh;

    $dbh->do("INSERT INTO s2layers (b2lid, userid, type) ".
             "VALUES (?,?,?)", undef, $b2lid, $userid, $type);
    return $dbh->{'mysql_insertid'};
}

sub delete_layer
{
    my $lid = shift;
    return 1 unless $lid;
    my $dbh = LJ::get_db_writer();
    foreach my $t (qw(s2layers s2compiled s2info s2source s2checker)) {
        $dbh->do("DELETE FROM $t WHERE s2lid=?", undef, $lid);
    }
    return 1;
}

sub set_style_layers
{
    my ($u, $styleid, %newlay) = @_;
    my $udbh = LJ::get_cluster_master($u);

    return 0 unless $udbh;
    $udbh->do("REPLACE INTO s2stylelayers (styleid,type,s2lid) VALUES ".
              join(",", map { sprintf("(%d,%s,%d)", $styleid,
                                      $udbh->quote($_), $newlay{$_}) }
                   keys %newlay));
    return 0 if $udbh->err;
    return 1;
}

sub load_layer
{
    my $db = ref $_[0] ? shift : LJ::get_db_reader();
    my $lid = shift;

    return $db->selectrow_hashref("SELECT s2lid, b2lid, userid, type ".
                                  "FROM s2layers WHERE s2lid=?", undef,
                                  $lid);
}

sub layer_compile_user
{
    my ($layer, $overrides) = @_;
    my $dbh = LJ::get_db_writer();
    return 0 unless ref $layer;
    return 0 unless $layer->{'s2lid'};
    return 1 unless ref $overrides;
    my $id = $layer->{'s2lid'};
    my $s2 = "layerinfo \"type\" = \"user\";\n";
   
    foreach my $name (keys %$overrides) {
        next if $name =~ /\W/;
        my $prop = $overrides->{$name}->[0];
        my $val = $overrides->{$name}->[1];
        if ($prop->{'type'} eq "int") {
            $val = int($val);
        } elsif ($prop->{'type'} eq "bool") {
            $val = $val ? "true" : "false";
        } else {
            $val =~ s/[\\\$\"]/\\$&/g;
            $val = "\"$val\"";
        }
        $s2 .= "set $name = $val;\n";
    }

    my $error;
    return 1 if LJ::layer_compile($layer, \$error, { 's2ref' => \$s2 });
    return LJ::error($error);
}

sub layer_compile
{
    my ($layer, $err_ref, $opts) = @_;
    my $dbh = LJ::get_db_writer();
    
    my $lid;
    if (ref $layer eq "HASH") {
        $lid = $layer->{'s2lid'}+0;
    } else {
        $lid = $layer+0;
        $layer = LJ::load_layer($dbh, $lid) or return 0;
    }
    return 0 unless $lid;
    
    # get checker (cached, or via compiling) for parent layer
    my $checker = get_layer_checker($layer);
    unless ($checker) {
        $$err_ref = "Error compiling parent layer.";
        return undef;
    }

    # do our compile (quickly, since we probably have the cached checker)
    my $s2ref = $opts->{'s2ref'};
    unless ($s2ref) {
        my $s2 = $dbh->selectrow_array("SELECT s2code FROM s2source WHERE s2lid=?", undef, $lid);
        unless ($s2) { $$err_ref = "No source code to compile.";  return undef; }
        $s2ref = \$s2;
    }

    my $untrusted = $layer->{'userid'} != LJ::get_userid($dbh, "system");

    my $compiled;
    my $cplr = S2::Compiler->new({ 'checker' => $checker });
    eval { 
        $cplr->compile_source({
            'type' => $layer->{'type'},
            'source' => $s2ref,
            'output' => \$compiled,
            'layerid' => $lid,
            'untrusted' => $untrusted,
            'builtinPackage' => "S2::Builtin::LJ",
        });
    };
    if ($@) { $$err_ref = "Compile error: $@"; return undef; }

    # save the source, since it at least compiles
    if ($opts->{'s2ref'}) {
        $dbh->do("REPLACE INTO s2source (s2lid, s2code) VALUES (?,?)",
                 undef, $lid, ${$opts->{'s2ref'}}) or return 0;
    }
    
    # save the checker object for later
    if ($layer->{'type'} eq "core" || $layer->{'type'} eq "layout") {
        $checker->cleanForFreeze();
        my $chk_frz = Storable::freeze($checker);
        $dbh->do("REPLACE INTO s2checker (s2lid, checker) VALUES (?,?)", undef,
                 $lid, $chk_frz) or die;
    }

    # load the compiled layer to test it loads and then get layerinfo/etc from it
    S2::unregister_layer($lid);
    eval $compiled;
    if ($@) { $$err_ref = "Post-compilation error: $@"; return undef; }
    if ($opts->{'redist_uniq'}) {
        # used by update-db loader:
        my $redist_uniq = S2::get_layer_info($lid, "redist_uniq");
        die "redist_uniq value of '$redist_uniq' doesn't match $opts->{'redist_uniq'}\n"
            unless $redist_uniq eq $opts->{'redist_uniq'};
    }
    
    # put layerinfo into s2info
    my %info = S2::get_layer_info($lid);
    my $values;
    my $notin;
    foreach (keys %info) {
        $values .= "," if $values;
        $values .= sprintf("(%d, %s, %s)", $lid,
                           $dbh->quote($_), $dbh->quote($info{$_}));
        $notin .= "," if $notin;
        $notin .= $dbh->quote($_);
    }
    if ($values) {
        $dbh->do("REPLACE INTO s2info (s2lid, infokey, value) VALUES $values") or die;
        $dbh->do("DELETE FROM s2info WHERE s2lid=? AND infokey NOT IN ($notin)", undef, $lid);
    }
    
    # put compiled into database, with its ID number
    $dbh->do("REPLACE INTO s2compiled (s2lid, comptime, compdata) ".
             "VALUES (?, UNIX_TIMESTAMP(), ?)", undef, $lid, $compiled) or die;

    # caller might want the compiled source
    if (ref $opts->{'compiledref'} eq "SCALAR") {
        ${$opts->{'compiledref'}} = $compiled;
    }
    
    S2::unregister_layer($lid);
    return 1;
}

sub get_layer_checker
{
    my $lay = shift;
    my $err_ref = shift;
    return undef unless ref $lay eq "HASH";
    return S2::Checker->new() if $lay->{'type'} eq "core";
    my $parid = $lay->{'b2lid'}+0 or return undef;
    my $dbh = LJ::get_db_writer();

    my $get_cached = sub {
        my $frz = $dbh->selectrow_array("SELECT checker FROM s2checker WHERE s2lid=?", 
                                        undef, $parid) or return undef;
        return Storable::thaw($frz); # can be undef, on failure
    };

    # the good path
    my $checker = $get_cached->();
    return $checker if $checker;

    # no cached checker (or bogus), so we have to [re]compile to get it
    my $parlay = LJ::load_layer($dbh, $parid);
    return undef unless LJ::layer_compile($parlay);
    return $get_cached->();
}

sub load_layer_info
{
    my ($outhash, $listref) = @_;
    return 0 unless ref $listref eq "ARRAY";
    return 1 unless @$listref;
    my $in = join(',', map { $_+0 } @$listref);
    my $dbr = LJ::get_db_reader();
    my $sth = $dbr->prepare("SELECT s2lid, infokey, value FROM s2info WHERE ".
                            "s2lid IN ($in)");
    $sth->execute;
    while (my ($id, $k, $v) = $sth->fetchrow_array) {
        $outhash->{$id}->{$k} = $v;
    }
    return 1;
}

#######################################

sub CommentInfo
{
    my $opts = shift;
    $opts->{'_type'} = "CommentInfo";
    $opts->{'count'} += 0;
    return $opts;
}

sub DateTime_parts
{
    my @parts = split(/\s+/, shift);
    my $dt = { '_type' => 'DateTime' };
    $dt->{'year'} = $parts[0]+0;
    $dt->{'month'} = $parts[1]+0;
    $dt->{'day'} = $parts[2]+0;
    $dt->{'hour'} = $parts[3]+0;
    $dt->{'min'} = $parts[4]+0;
    $dt->{'sec'} = $parts[5]+0;
    $dt->{'_dayofweek'} = $parts[6];
    return $dt;
}

sub Entry
{
    my ($u, $arg) = @_;
    my $e = {
        '_type' => 'Entry',
        'links' => {}, # TODO: finish
    };
    foreach (qw(subject text journal poster new_day end_day comments 
                userpic permalink_url itemid)) {
        $e->{$_} = $arg->{$_};
    }

    $e->{'time'} = DateTime_parts($arg->{'dateparts'});
    
    if ($arg->{'security'} eq "public") {
        # do nothing.
    } elsif ($arg->{'security'} eq "usemask") {
        $e->{'security'} = "protected";
        $e->{'security_icon'} = Image_std("security-protected");
    } elsif ($arg->{'security'} eq "private") {
        $e->{'security'} = "private";
        $e->{'security_icon'} = Image_std("security-private");
    }

    return $e;
}

sub Null
{   
    my $type = shift;
    return {
        '_type' => $type,
        '_isnull' => 1,
    };
}

sub Page
{
    my ($u, $vhost) = @_;
    my $base_url = LJ::journal_base($u->{'user'}, $vhost);
    my $p = {
        '_type' => 'Page',
        'view' => '',
        'journal' => User($u),
        'journal_type' => $u->{'journaltype'},
        'base_url' => $base_url,
        'views' => {
            'lastn' => "$base_url/",
            'calendar' => "$base_url/calendar",
            'friends' => "$base_url/friends",
        },
        'views_order' => [ 'lastn', 'calendar', 'friends' ],
        'stylesheet_url' => "$base_url/res/stylesheet",
        'global_title' => '',
        'head_content' => '',
    };
    return $p;
}

sub RecentPage
{
    my ($u, $remote, $opts) = @_;

    my $p = Page($u, $opts->{'vhost'});
    $p->{'_type'} = "RecentPage";
    $p->{'view'} = "recent";
    $p->{'entries'} = [];

    my $dbs = LJ::get_dbs();
    my $dbh = $dbs->{'dbh'};
    my $dbr = $dbs->{'reader'};
    my $dbcr;
    if ($u->{'clusterid'}) {
        $dbcr = LJ::get_cluster_reader($u);
    }
    my $user = $u->{'user'};

    if ($u->{'journaltype'} eq "R" && $u->{'renamedto'} ne "") {
        $opts->{'redir'} = LJ::journal_base($u->{'renamedto'}, $opts->{'vhost'});
        return;
    }

    LJ::load_user_props($dbs, $remote, "opt_nctalklinks");

    my %FORM = ();
    LJ::decode_url_string($opts->{'args'}, \%FORM);

    if ($opts->{'pathextra'}) {
        $opts->{'badargs'} = 1;
        return 1;
    }
    
    if ($u->{'opt_blockrobots'}) {
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex\">\n";
    }

    if ($FORM{'skip'}) {
        # if followed a skip link back, prevent it from going back further
        $p->{'head_content'} = "<meta name=\"robots\" content=\"noindex,nofollow\">\n";
    }
    if ($LJ::UNICODE) {
        $p->{'head_content'} .= '<meta http-equiv="Content-Type" content="text/html; charset='.$opts->{'saycharset'}."\">\n";
    }

    # "Automatic Discovery of RSS feeds"
    $p->{'head_content'} .= qq{<link rel="alternate" type="application/rss+xml" title="RSS" href="$p->{'base_url'}/rss" />\n};
    
    my $quser = $dbh->quote($user);
    
    my $itemshow = S2::get_property_value($opts->{'ctx'}, "page_recent_items")+0;
    if ($itemshow < 1) { $itemshow = 20; }
    elsif ($itemshow > 50) { $itemshow = 50; }
    

    my $skip = $FORM{'skip'}+0;
    my $maxskip = $LJ::MAX_HINTS_LASTN-$itemshow;
    if ($skip < 0) { $skip = 0; }
    if ($skip > $maxskip) { $skip = $maxskip; }

    # do they want to view all entries, regardless of security?
    my $viewall = 0;
    if ($FORM{'viewall'} && LJ::check_priv($dbs, $remote, "viewall")) {
        LJ::statushistory_add($dbs, $u->{'userid'}, $remote->{'userid'}, 
                              "viewall", "lastn: $user");
        $viewall = 1;
    }

    ## load the itemids
    my @itemids;
    my $err;
    my @items = LJ::get_recent_items($dbs, {
        'clusterid' => $u->{'clusterid'},
        'clustersource' => 'slave',
        'viewall' => $viewall,
        'userid' => $u->{'userid'},
        'remote' => $remote,
        'itemshow' => $itemshow,
        'skip' => $skip,
        'itemids' => \@itemids,
        'dateformat' => 'S2',
        'order' => ($u->{'journaltype'} eq "C" || $u->{'journaltype'} eq "Y")  # community or syndicated
            ? "logtime" : "",
        'err' => \$err,
    });

    die $err if $err;
    
    ### load the log properties
    my %logprops = ();
    my $logtext;
    if ($u->{'clusterid'}) {
        LJ::load_props($dbs, "log");
        LJ::load_log_props2($dbcr, $u->{'userid'}, \@itemids, \%logprops);
        $logtext = LJ::get_logtext2($u, @itemids);
    } else {
        LJ::load_log_props($dbs, \@itemids, \%logprops);
        $logtext = LJ::get_logtext($dbs, @itemids);
    }
    LJ::load_moods($dbs);

    my $lastdate = "";
    my $itemnum = 0;
    my $lastentry = undef;

    my (%apu, %apu_lite);  # alt poster users; UserLite objects
    foreach (@items) {
        next unless $_->{'posterid'} != $u->{'userid'};
        $apu{$_->{'posterid'}} = undef;
    }
    if (%apu) {
        my $in = join(',', keys %apu);
        my $sth = $dbr->prepare("SELECT userid, user, defaultpicid, statusvis, name, journaltype ".
                                "FROM user WHERE userid IN ($in)");
        $sth->execute;
        while ($_ = $sth->fetchrow_hashref) {
            $apu{$_->{'userid'}} = $_;
            $apu_lite{$_->{'userid'}} = UserLite($_);
        }
    }

    my $userlite_journal = UserLite($u);

    foreach my $item (@items) 
    {
        my ($posterid, $itemid, $security, $alldatepart, $replycount) = 
            map { $item->{$_} } qw(posterid itemid security alldatepart replycount);

        my $subject = $logtext->{$itemid}->[0];
        my $text = $logtext->{$itemid}->[1];

	if ($LJ::UNICODE && $logprops{$itemid}->{'unknown8bit'}) {
	    LJ::item_toutf8($dbs, $u, \$subject, \$text, $logprops{$itemid});
	}

        my $date = substr($alldatepart, 0, 10);
        my $new_day = 0;
        if ($date ne $lastdate) {
            $new_day = 1;
            $lastdate = $date;
            $lastentry->{'end_day'} = 1 if $lastentry;
        }

        $itemnum++;
        LJ::CleanHTML::clean_subject(\$subject) if $subject;

        my $ditemid = $u->{'clusterid'} ? ($itemid * 256 + $item->{'anum'}) : $itemid;
        my $itemargs = $u->{'clusterid'} ? "journal=$user&itemid=$ditemid" : "itemid=$ditemid";
        LJ::CleanHTML::clean_event(\$text, { 'preformatted' => $logprops{$itemid}->{'opt_preformatted'},
                                              'cuturl' => LJ::item_link($u, $itemid, $item->{'anum'}), });
        LJ::expand_embedded($dbs, $ditemid, $remote, \$text);

        my $nc;
        $nc .= "&nc=$replycount" if $replycount && $remote && $remote->{'opt_nctalklinks'};
        
        my $readurl = "$LJ::SITEROOT/talkread.bml?$itemargs$nc";
        my $comments = CommentInfo({
            'read_url' => $readurl,
            'post_url' => "$LJ::SITEROOT/talkpost.bml?$itemargs",
            'count' => $replycount,
            'enabled' => ($u->{'opt_showtalklinks'} eq "Y" && ! $logprops{$itemid}->{'opt_nocomments'}) ? 1 : 0,
            'screened' => ($logprops{$itemid}->{'hasscreened'} && ($remote->{'user'} eq $u->{'user'}|| LJ::check_priv($dbs, $remote, "sharedjournal", $user))) ? 1 : 0,
        });
        
        my $userlite_poster = $userlite_journal;
        my $userpic = $p->{'journal'}->{'default_pic'};
        if ($u->{'userid'} != $posterid) {
            $userlite_poster = $apu_lite{$posterid} or die "No apu_lite for posterid=$posterid";
            $userpic = Image_userpic($apu{$posterid}, 0, $logprops{$itemid}->{'picture_keyword'});
        }

        my $entry = $lastentry = Entry($u, {
            'subject' => $subject,
            'text' => $text,
            'dateparts' => $alldatepart,
            'security' => $security,
            'props' => \%logprops,
            'itemid' => $ditemid,
            'journal' => $userlite_journal,
            'poster' => $userlite_poster,
            'comments' => $comments,
            'new_day' => $new_day,
            'end_day' => 0,   # if true, set later
            'userpic' => $userpic,

        });

        push @{$p->{'entries'}}, $entry;

    } # end huge while loop


    #### make the skip links
    my $nav = {
        '_type' => 'RecentNav',
        'version' => 1,
        'skip' => $skip,
    };

    # if we've skipped down, then we can skip back up
    if ($skip) {
        my $newskip = $skip - $itemshow;
        $newskip = 0 if $newskip <= 0;
        $nav->{'forward_skip'} = $newskip;
        $nav->{'forward_url'} = $newskip ? "$p->{'base_url'}/?skip=$newskip" : "$p->{'base_url'}/";
        $nav->{'forward_count'} = $itemshow;
    }

    # unless we didn't even load as many as we were expecting on this
    # page, then there are more (unless there are exactly the number shown 
    # on the page, but who cares about that)
    unless ($itemnum != $itemshow) {
        $p->{'backward_count'} = $itemshow;
        if ($skip == $maxskip) {
            my $date_slashes = $lastdate;  # "yyyy mm dd";
            $date_slashes =~ s! !/!g;
            $p->{'backward_url'} = "$p->{'base_url'}/day/$date_slashes";
        } else {
            my $newskip = $skip + $itemshow;
            $p->{'backward_url'} = "$p->{'base_url'}/?skip=$newskip";
            $p->{'backward_skip'} = $newskip;
        }
    }

    $p->{'nav'} = $nav;
    return $p;
}

sub Image
{
    my ($url, $w, $h) = @_;
    return {
        '_type' => 'Image',
        'url' => $url,
        'width' => $w,
        'height' => $h,
    };
}

sub Image_std
{
    my $name = shift;
    unless ($LJ::S2::RES_MADE++) {
        $LJ::S2::RES_CACHE = {
            'security-protected' => Image("$LJ::IMGPREFIX/icon_protected.gif", 14, 15),
            'security-private' => Image("$LJ::IMGPREFIX/icon_private.gif", 16, 16),
        };
    }
    return $LJ::S2::RES_CACHE->{$name};
}

sub Image_userpic
{
    my ($u, $picid, $kw) = @_;
    unless ($u->{'_userpics'}) {
        my $dbr = LJ::get_db_reader();
        my $sth = $dbr->prepare("SELECT picid, width, height FROM userpic ".
                                "WHERE userid=?");
        $sth->execute($u->{'userid'});
        while (my ($id, $w, $h) = $sth->fetchrow_array) {
            $u->{'_userpics'}->{$id} = [ $w, $h ];
        }
        $sth = $dbr->prepare("SELECT m.picid, k.keyword FROM userpicmap m, keywords k ".
                             "WHERE m.userid=? AND m.kwid=k.kwid");
        $sth->execute($u->{'userid'});
        while (my ($id, $kw) = $sth->fetchrow_array) {
            $u->{'_userpics'}->{'kw'}->{$kw} = $id;
        }
    }

    unless ($picid) {
        $picid = $kw ? $u->{'_userpics'}->{'kw'}->{$kw} : $u->{'defaultpicid'};
    }

    return Null("Image") unless defined $u->{'_userpics'}->{$picid};
    my $p = $u->{'_userpics'}->{$picid};
    return {
        '_type' => "Image",
        'url' => "$LJ::SITEROOT/userpic/$picid",
        'width' => $p->[0],
        'height' => $p->[1],
    };
}

sub User
{
    my ($u) = @_;
    my $o = UserLite($u);
    $o->{'_type'} = "User";
    $o->{'default_pic'} = Image_userpic($u, $u->{'defaultpicid'});
    $o->{'website_url'} = LJ::ehtml($u->{'url'});
    $o->{'website_name'} = LJ::ehtml($u->{'urlname'});
    return $o;
}

sub UserLite
{
    my ($u) = @_;
    my $o = {
        '_type' => 'UserLite',
        'username' => $u->{'user'},
        'name' => $u->{'name'},
        'journal_type' => $u->{'journaltype'},
    };
    return $o;
}

###############

package S2::Builtin::LJ;
use strict;

sub AUTOLOAD { 
    no strict;
    if ($AUTOLOAD =~ /::(\w+)$/) {
        my $real = \&{"S2::Builtin::$1"};
        *{$AUTOLOAD} = $real;
        return $real->(@_);
    }
    die "No such builtin: $AUTOLOAD";
}

sub ehtml
{
    my ($ctx, $text) = @_;
    return LJ::ehtml($text);
}

sub get_page
{
    return $LJ::S2::CURR_PAGE;
}

sub get_plural_phrase
{
    my ($ctx, $n, $prop) = @_;
    my $form = S2::run_function($ctx, "lang_map_plural(int)", $n);
    my $a = $ctx->[S2::PROPS]->{"_plurals_$prop"};
    unless (ref $a eq "ARRAY") {
        $a = $ctx->[S2::PROPS]->{"_plurals_$prop"} = [ split(m!\s*//\s*!, $ctx->[S2::PROPS]->{$prop}) ];
    }
    my $text = $a->[$form];
    $text =~ s/\#/$n/;
    return LJ::ehtml($text);
}

sub get_url
{
    my ($ctx, $obj, $view) = @_;
    my $user = ref $obj ? $obj->{'username'} : $obj;
    $view = "info" if $view eq "userinfo";
    $view = "" if $view eq "recent";
    return "$LJ::SITEROOT/$user/$view";
}

sub rand
{
    my ($ctx, $aa, $bb) = @_;
    my ($low, $high);
    if (ref $aa eq "ARRAY") {
        ($low, $high) = (0, @$aa - 1);
    } elsif (! defined $bb) {
        ($low, $high) = (1, $aa);
    } else {
        ($low, $high) = ($aa, $bb);
    }
    return int(rand($high - $low + 1)) + $low;
}

sub Date__day_of_week
{
    my ($ctx, $dt) = @_;
    return $dt->{'_dayofweek'} if defined $dt->{'_dayofweek'};
    die "FIXME: finish Date::day_of_week";
}
*DateTime__day_of_week = \&Date__day_of_week;

my %dt_vars = (
               'm' => "\$time->{month}",
               'mm' => "sprintf('%02d', \$time->{month})",
               'd' => "\$time->{day}",
               'dd' => "sprintf('%02d', \$time->{day})",
               'yy' => "sprintf('%02d', \$time->{year} % 100)",
               'yyyy' => "\$time->{year}",
               'mon' => "\$ctx->[S2::PROPS]->{lang_monthname_short}->[\$time->{month}]",
               'month' => "\$ctx->[S2::PROPS]->{lang_monthname_long}->[\$time->{month}]",
               'da' => "\$ctx->[S2::PROPS]->{lang_dayname_short}->[Date__day_of_week(\$ctx, \$time)]",
               'day' => "\$ctx->[S2::PROPS]->{lang_dayname_long}->[Date__day_of_week(\$ctx, \$time)]",
               'dayord' => "S2::run_function(\$ctx, \"lang_ordinal(int)\", \$time->{day})",
               'H' => "\$time->{hour}",
               'HH' => "sprintf('%02d', \$time->{hour})",
               'h' => "(\$time->{hour} % 12 || 12)",
               'hh' => "sprintf('%02d', (\$time->{hour} % 12 || 12))",
               'mm' => "sprintf('%02d', \$time->{min})",
               'a' => "(\$time->{hour} < 12 ? 'a' : 'p')",
               'A' => "(\$time->{hour} < 12 ? 'A' : 'P')",
            );

sub Date__date_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_datefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_datefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_date_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join(";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}
*DateTime__date_format = \&Date__date_format;

sub DateTime__time_format
{
    my ($ctx, $this, $fmt) = @_;
    $fmt ||= "short";
    my $c = \$ctx->[S2::SCRATCH]->{'_code_timefmt'}->{$fmt};
    return $$c->($this) if ref $$c eq "CODE";
    if (++$ctx->[S2::SCRATCH]->{'_code_timefmt_count'} > 15) { return "[too_many_fmts]"; }
    my $realfmt = $fmt;
    if (defined $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"}) {
        $realfmt = $ctx->[S2::PROPS]->{"lang_fmt_time_$fmt"};
    }
    my @parts = split(/\%\%/, $realfmt);
    my $code = "\$\$c = sub { my \$time = shift; return join(";
    my $i = 0;
    foreach (@parts) {
        if ($i % 2) { $code .= $dt_vars{$_} . ","; }
        else { $_ = LJ::ehtml($_); $code .= "\$parts[$i],"; }
        $i++;
    }
    $code .= "); };";
    eval $code;
    return $$c->($this);
}


1;
