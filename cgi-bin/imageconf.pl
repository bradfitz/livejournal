#!/usr/bin/perl
#

use strict;
package LJ::Img;
use vars qw(%img);

$img{'btn_up'} = {
    'src' => '/btn_up.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Up',
};

$img{'btn_down'} = { 
    'src' => '/btn_dn.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Down',
};

$img{'btn_del'} = { 
    'src' => '/btn_del.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Delete',
};

$img{'btn_scr'} = { 
    'src' => '/btn_scr.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Screen',
};

$img{'btn_unscr'} = { 
    'src' => '/btn_unscr.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Unscreen',
};

$img{'prev_entry'} = { 
    'src' => '/btn_prev.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Previous Entry',
};

$img{'next_entry'} = { 
    'src' => '/btn_next.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Next Entry',
};

$img{'memadd'} = { 
    'src' => '/memadd.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Add to memories!',
};

$img{'editentry'} = { 
    'src' => '/btn_edit.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Edit Entry',
};

$img{'tellfriend'} = { 
    'src' => '/btn_tellfriend.gif',
    'width' => 22,
    'height' => 20,
    'alt' => 'Tell a Friend!',
};

# load the site-local version, if it's around.
if (-e "$LJ::HOME/cgi-bin/imageconf-local.pl") {
    require "$LJ::HOME/cgi-bin/imageconf-local.pl";
}

1;

