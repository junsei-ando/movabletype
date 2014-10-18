#!/usr/bin/perl

use strict;
use warnings;

BEGIN {
    $ENV{MT_CONFIG} = 'mysql-test.cfg';
}

BEGIN {
    use Test::More;
    eval { require Test::MockModule }
        or plan skip_all => 'Test::MockModule is not installed';
}

use lib qw(lib extlib t/lib);

eval(
    $ENV{SKIP_REINITIALIZE_DATABASE}
    ? "use MT::Test qw(:app);"
    : "use MT::Test qw(:app :db :data);"
);

use MT::Theme;
use MT::App::DataAPI;
my $app    = MT::App::DataAPI->new;
my $author = MT->model('author')->load(1);
$author->email('melody@example.com');
$author->save;

my $mock_author = Test::MockModule->new('MT::Author');
$mock_author->mock( 'is_superuser', sub {0} );
my $mock_app_api = Test::MockModule->new('MT::App::DataAPI');
$mock_app_api->mock( 'authenticate', $author );
my $version;
$mock_app_api->mock( 'current_api_version',
    sub { $version = $_[1] if $_[1]; $version } );

my @suite = (

    # list_widgets - irregular tests
    {   path   => '/v2/sites/5/widgets',
        method => 'GET',
        code   => 404,
    },

    # list_widgets - normal tests
    {   path   => '/v2/sites/1/widgets',
        method => 'GET',
    },

    # get_widget - irregular tests
    {    # Non-existent widget.
        path   => '/v2/sites/1/widgets/500',
        method => 'GET',
        code   => 404,
    },
    {    # Non-existent site.
        path   => '/v2/sites/5/widgets/132',
        method => 'GET',
        code   => 404,
    },
    {    # Other site.
        path   => '/v2/sites/2/widgets/132',
        method => 'GET',
        code   => 404,
    },
    {    # Other site (system).
        path   => '/v2/sites/0/widgets/132',
        method => 'GET',
        code   => 404,
    },

    # get_widget - normal tests
    {   path   => '/v2/sites/1/widgets/132',
        method => 'GET',
        result => sub {
            $app->model('template')->load(132);
        },
    },

    # creat_widget - irregular tests
    {    # No resource.
        path     => '/v2/sites/1/widgets',
        method   => 'POST',
        code     => 400,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body, 'A resource "widget" is required.' );
        },
    },
    {    # No name.
        path     => '/v2/sites/1/widgets',
        method   => 'POST',
        params   => { widget => {}, },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"name\" is required.\n" );
        },
    },

    # create_widget - normal tests
    {   path   => '/v2/sites/1/widgets',
        method => 'POST',
        params => { widget => { name => 'create-widget', }, },
        result => sub {
            $app->model('template')->load(
                {   name    => 'create-widget',
                    blog_id => 1,
                    type    => 'widget',
                }
            );
        },
    },
    {   path   => '/v2/sites/0/widgets',
        method => 'POST',
        params => { widget => { name => 'create-widget-system', }, },
        result => sub {
            $app->model('template')->load(
                {   name    => 'create-widget-system',
                    blog_id => 0,
                    type    => 'widget',
                }
            );
        },
    },

    # update_widget - irregular tests
    {    # No resource.
        path     => '/v2/sites/1/widgets/132',
        method   => 'PUT',
        code     => 400,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body, 'A resource "widget" is required.' );
        },
    },
    {    # Empty name.
        path     => '/v2/sites/1/widgets/132',
        method   => 'PUT',
        params   => { widget => { name => '', }, },
        code     => 409,
        complete => sub {
            my ( $data, $body ) = @_;
            check_error_message( $body,
                "A parameter \"name\" is required.\n" );
        },
    },

    # update_widget - normal tests
    {   path   => '/v2/sites/1/widgets/132',
        method => 'PUT',
        params => {
            widget => {
                name => 'update-widget',
                type => 'update-type',
            },
        },
        result => sub {
            $app->model('template')->load(
                {   name    => 'update-widget',
                    blog_id => 1,
                    type    => 'widget',
                }
            );
        },
    },

    # refresh_widget - irregular tests
    {    # Non-existent widget.
        path   => '/v2/sites/1/widgets/500/refresh',
        method => 'POST',
        code   => 404,
    },
    {    # Non-existent site.
        path   => '/v2/sites/5/widgets/132/refresh',
        method => 'POST',
        code   => 404,
    },
    {    # Other site.
        path   => '/v2/sites/2/widgets/132/refresh',
        method => 'POST',
        code   => 404,
    },
    {    # Other site (system).
        path   => '/v2/sites/0/widgets/132/refresh',
        method => 'POST',
        code   => 404,
    },
    {    # Not widget (index template).
        path   => '/v2/sites/0/widgets/133/refresh',
        method => 'POST',
        code   => 404,
    },

    # refresh_widget - normal tests
    {   path   => '/v2/sites/1/widgets/132/refresh',
        method => 'POST',
    },

    # clone_widget - irregular tests
    {    # Non-existent widget.
        path   => '/v2/sites/1/widgets/500/clone',
        method => 'POST',
        code   => 404,
    },
    {    # Non-existent site.
        path   => '/v2/sites/5/widgets/132/clone',
        method => 'POST',
        code   => 404,
    },
    {    # Other site.
        path   => '/v2/sites/2/widgets/132/clone',
        method => 'POST',
        code   => 404,
    },
    {    # Other site (system).
        path   => '/v2/sites/0/widgets/132/clone',
        method => 'POST',
        code   => 404,
    },
    {    # Not widget (index template).
        path   => '/v2/sites/0/widgets/133/clone',
        method => 'POST',
        code   => 404,
    },

    # clone_widget - normal tests
    {   path   => '/v2/sites/1/widgets/132/clone',
        method => 'POST',
    },

    # delete_widget - irregular tests
    {    # Non-existent widget.
        path   => '/v2/sites/1/widgets/500',
        method => 'DELETE',
        code   => 404,
    },
    {    # Non-existent site.
        path   => '/v2/sites/5/widgets/132',
        method => 'DELETE',
        code   => 404,
    },
    {    # Other site.
        path   => '/v2/sites/2/widgets/132',
        method => 'DELETE',
        code   => 404,
    },
    {    # Other site (system).
        path   => '/v2/sites/0/widgets/132',
        method => 'DELETE',
        code   => 404,
    },

    # delete_widget - normal tests
    {   path   => '/v2/sites/1/widgets/132',
        method => 'DELETE',
        setup  => sub {
            die if !$app->model('template')->load(132);
        },
        complete => sub {
            my $widget = $app->model('template')->load(132);
            is( $widget, undef, 'Deleted widget.' );
        },
    },
);

my %callbacks = ();
my $mock_mt   = Test::MockModule->new('MT');
$mock_mt->mock(
    'run_callbacks',
    sub {
        my ( $app, $meth, @param ) = @_;
        $callbacks{$meth} ||= [];
        push @{ $callbacks{$meth} }, \@param;
        $mock_mt->original('run_callbacks')->(@_);
    }
);

my $format = MT::DataAPI::Format->find_format('json');

for my $data (@suite) {
    $data->{setup}->($data) if $data->{setup};

    my $path = $data->{path};
    $path
        =~ s/:(?:(\w+)_id)|:(\w+)/ref $data->{$1} ? $data->{$1}->id : $data->{$2}/ge;

    my $params
        = ref $data->{params} eq 'CODE'
        ? $data->{params}->($data)
        : $data->{params};

    my $note = $path;
    if ( lc $data->{method} eq 'get' && $data->{params} ) {
        $note .= '?'
            . join( '&',
            map { $_ . '=' . $data->{params}{$_} }
                keys %{ $data->{params} } );
    }
    $note .= ' ' . $data->{method};
    $note .= ' ' . $data->{note} if $data->{note};
    note($note);

    %callbacks = ();
    _run_app(
        'MT::App::DataAPI',
        {   __path_info      => $path,
            __request_method => $data->{method},
            ( $data->{upload} ? ( __test_upload => $data->{upload} ) : () ),
            (   $params
                ? map {
                    $_ => ref $params->{$_}
                        ? MT::Util::to_json( $params->{$_} )
                        : $params->{$_};
                    }
                    keys %{$params}
                : ()
            ),
        }
    );
    my $out = delete $app->{__test_output};
    my ( $headers, $body ) = split /^\s*$/m, $out, 2;
    my %headers = map {
        my ( $k, $v ) = split /\s*:\s*/, $_, 2;
        $v =~ s/(\r\n|\r|\n)\z//;
        lc $k => $v
        }
        split /\n/, $headers;
    my $expected_status = $data->{code} || 200;
    is( $headers{status}, $expected_status, 'Status ' . $expected_status );
    if ( $data->{next_phase_url} ) {
        like(
            $headers{'x-mt-next-phase-url'},
            $data->{next_phase_url},
            'X-MT-Next-Phase-URL'
        );
    }

    foreach my $cb ( @{ $data->{callbacks} } ) {
        my $params_list = $callbacks{ $cb->{name} } || [];
        if ( my $params = $cb->{params} ) {
            for ( my $i = 0; $i < scalar(@$params); $i++ ) {
                is_deeply( $params_list->[$i], $cb->{params}[$i] );
            }
        }

        if ( my $c = $cb->{count} ) {
            is( @$params_list, $c,
                $cb->{name} . ' was called ' . $c . ' time(s)' );
        }
    }

    if ( my $expected_result = $data->{result} ) {
        $expected_result = $expected_result->( $data, $body )
            if ref $expected_result eq 'CODE';
        if ( UNIVERSAL::isa( $expected_result, 'MT::Object' ) ) {
            MT->instance->user($author);
            $expected_result = $format->{unserialize}->(
                $format->{serialize}->(
                    MT::DataAPI::Resource->from_object($expected_result)
                )
            );
        }

        my $result = $format->{unserialize}->($body);
        is_deeply( $result, $expected_result, 'result' );
    }

    if ( my $complete = $data->{complete} ) {
        $complete->( $data, $body );
    }
}

done_testing();

sub check_error_message {
    my ( $body, $error ) = @_;
    my $result = $app->current_format->{unserialize}->($body);
    is( $result->{error}{message}, $error, 'Error message: ' . $error );
}
