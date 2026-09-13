#!/usr/bin/perl

use strict;
use warnings;

use C4::Context;

# Wrap Koha's packaged PSGI application rather than replacing it. This keeps
# /healthz outside the normal OPAC/intranet request paths (and therefore out of
# Koha's session handling) while still exercising the same Starman workers.
my $koha_app = do '/etc/koha/plack.psgi';
if (!$koha_app || ref($koha_app) ne 'CODE') {
    die "Unable to load /etc/koha/plack.psgi: $@ $!";
}

sub response {
    my ($status, $body) = @_;

    return [
        $status,
        [
            'Content-Type'   => 'text/plain; charset=utf-8',
            'Cache-Control'  => 'no-store',
            'Content-Length' => length($body),
        ],
        [$body],
    ];
}

my $app = sub {
    my ($env) = @_;

    if (($env->{PATH_INFO} // '') eq '/healthz') {
        my $ok = eval {
            my $dbh = C4::Context->dbh;
            my ($value) = $dbh->selectrow_array('SELECT 1');

            die "SELECT 1 returned an unexpected result"
                unless defined($value) && $value == 1;

            1;
        };

        if (!$ok) {
            my $error = $@ || 'unknown database error';
            $error =~ s/\s+$//;
            warn "healthz: database check failed: $error\n";

            return response(503, "unhealthy\n");
        }

        return response(200, "ok\n");
    }

    return $koha_app->($env);
};

$app;
