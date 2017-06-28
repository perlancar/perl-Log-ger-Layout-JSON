package Log::ger::Layout::JSON;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Log::ger ();
use Time::HiRes qw(time);

our $caller_depth_offset = 3;

our $time_start = time();
our $time_now   = $time_start;
our $time_last  = $time_start;

sub _encode {
    state $json = do {
        require JSON::MaybeXS;
        JSON::MaybeXS->new->canonical;
    };
    $json->encode(shift);
}

sub _layouter {
    my ($conf, $msg0, $init_args, $lnum, $level) = @_;

    ($time_last, $time_now) = ($time_now, time());

    my @pmd; # per-message data

    my $msg;
    if (ref $msg0 eq 'HASH') {
        $msg = {%$msg0};
    } else {
        $msg = {message => $msg0};
    }

    if ($conf->{delete_fields}) {
        for my $f (@{ $conf->{delete_fields} }) {
            if (ref $f eq 'Regexp') {
                for my $k (keys %$msg) {
                    delete $msg->{$k} if $k =~ $f;
                }
            } else {
                delete $msg->{$f};
            }
        }
    }

    if (my $ff = $conf->{add_fields}) {
        for my $f (keys %$ff) {
            $msg->{$f} = $ff->{$f};
        }
    }

    if (my $ff = $conf->{add_special_fields}) {
        for my $f (keys %$ff) {
            my $sf = $ff->{$f};
            my $val;
            if ($sf eq 'Category') {
                $val = $init_args->{category};
            } elsif ($sf eq 'Class') {
                $pmd[0] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset)];
                $pmd[1] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset-1)];
                $val = $pmd[0][0] // $pmd[1][0];
            } elsif ($sf eq 'Date_Local') {
                my @t = localtime($time_now);
                $val = sprintf(
                    "%04d-%02d-%02dT%02d:%02d:%02d",
                    $t[5]+1900, $t[4]+1, $t[3],
                    $t[2], $t[1], $t[0],
                );
            } elsif ($sf eq 'Date_GMT') {
                my @t = gmtime($time_now);
                $val = sprintf(
                    "%04d-%02d-%02dT%02d:%02d:%02d",
                    $t[5]+1900, $t[4]+1, $t[3],
                    $t[2], $t[1], $t[0],
                );
            } elsif ($sf eq 'File') {
                $pmd[0] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset)];
                $pmd[1] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset-1)];
                $val = $pmd[0][1] // $pmd[1][1];
            } elsif ($sf eq 'Hostname') {
                require Sys::Hostname;
                $val = Sys::Hostname::hostname();
            } elsif ($sf eq 'Location') {
                $pmd[0] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset)];
                $pmd[1] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset-1)];
                $val = sprintf(
                    "%s (%s:%d)",
                    $pmd[0][3] // $pmd[1][3],
                    $pmd[1][1],
                    $pmd[1][2],
                );
            } elsif ($sf eq 'Line') {
                $pmd[0] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset)];
                $pmd[1] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset-1)];
                $val = $pmd[1][2];
            } elsif ($sf eq 'Message') {
                $val = $msg0;
            } elsif ($sf eq 'Method') {
                $pmd[0] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset)];
                $pmd[1] //= [caller($Log::ger::Caller_Depth_Offset+$caller_depth_offset-1)];
                $val = $pmd[0][3] // $pmd[1][3];
                $val =~ s/.+:://;
            } elsif ($sf eq 'Level') {
                $val = $level;
            } elsif ($sf eq 'PID') {
                $val = $$;
            } elsif ($sf eq 'Elapsed_Start') {
                $val = $time_now - $time_start;
            } elsif ($sf eq 'Elapsed_Last') {
                $val = $time_now - $time_last;
            } elsif ($sf eq 'Stack_Trace') {
                $pmd[2] //= do {
                    my @st;
                    my $i = $Log::ger::Caller_Depth_Offset+$caller_depth_offset-1;
                    while (my @c = caller($i++)) {
                        push @st, \@c;
                    }
                    \@st;
                };
                $val = [];
                for my $frame (@{ $pmd[2] }) {
                    push @$val, {file=>$frame->[1], line=>$frame->[2], method=>$frame->[3]};
                }
            } else { die "Unknown special field '$f'" }
            $msg->{$f} = $val;
        }
    }
    _encode($msg);
}

sub get_hooks {
    my %conf = @_;

    return {
        create_layouter => [
            __PACKAGE__, 50,
            sub {
                my %args = @_;

                [sub { _layouter(\%conf, @_) }];
            }],
    };
}

1;
# ABSTRACT: Layout log message as a JSON object (hash)

=for Pod::Coverage ^(.+)$

=head1 SYNOPSIS

 use Log::ger::Layout JSON => (
     add_fields         => {key3 => 'value', key4 => 'value', ...},         # optional
     add_special_fields => {_date => 'Date_GMT', _host => 'Hostname', ...}, # optional
     delete_fields      => ['key1', 'key2', qr/some-regex/, ...],           # optional
 );
 use Log::ger;

 # if you use it together with Log::ger::Format::None:
 log_warn({key1 => 'val1', key2 => 'val2', foo => 'bar', ...);

 # otherwise, using the standard formatter:
 log_warn("blah %s", ['some', 'data']);

The final message will be something like:

 {"foo":"bar", "key3":"value", "key4":"value", "_date":"2017-06-28T14:08:22", "_host":"example.com"}

or:

 {"message":"blah [\"some\",\"data\"]", "_date":"2017-06-28T14:08:22", "_host":"example.com"}


=head1 DESCRIPTION

This layouter allows you to log as JSON. If you use L<Log::ger::Format::None>,
you can pass a hashref. Otherwise, the message will be put in C<message> key.
You can then delete keys then add additional fields/keys (including special
fields, a la L<Log::ger::Layout::Pattern>).


=head1 CONFIGURATION

=head2 add_fields => hash

=head2 add_special_fields => hash

Known special fields:

 Category: Category of the logging event
 Class: Fully qualified package [or class] name of the caller
 Date_Local: Current date in ISO8601 format (YYYY-MM-DD<T>hh:mm:ss) (localtime)
 Date_GMT: Current date in ISO8601 format (YYYY-MM-DD<T>hh:mm:ss) (GMT)
 File: File where the logging event occurred
 Hostname: (if Sys::Hostname is available)
 Location: Fully qualified name of the calling method followed by the
   callers source the file name and line number between parentheses.
 Line: Line number within the file where the log statement was issued
 Message: The message to be logged
 Method: Method or function where the logging request was issued
 Level: Level ("priority") of the logging event
 PID: PID of the current process
 Elapsed_Start: Number of seconds elapsed from program start to logging event
 Elapsed_Last: Number of seconds elapsed from last logging event to current
   logging event
 Stack_Trace: stack trace of functions called

Unknown special fields will cause the layouter to die.

=head2 delete_fields


=head1 SEE ALSO

L<Log::ger>

L<Log::ger::Layout::Pattern>

=cut
