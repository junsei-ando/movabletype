#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../lib";    # t/lib
use Test::More;
use MT::Test::Env;
our $test_env;

BEGIN {
    $test_env = MT::Test::Env->new;
    $ENV{MT_CONFIG} = $test_env->config_file;
}

use MT::Test::Tag;

# plan tests => 2 * blocks;
plan tests => 1 * blocks;

use MT;
use MT::Test;
use MT::Test::Permission;

use MT::ContentStatus;

my $app = MT->instance;

my $blog_id = 1;

my $vars = {};

sub var {
    for my $line (@_) {
        for my $key ( keys %{$vars} ) {
            my $replace = quotemeta "[% ${key} %]";
            my $value   = $vars->{$key};
            $line =~ s/$replace/$value/g;
        }
    }
    @_;
}

filters {
    template => [qw( var chomp )],
    expected => [qw( var chomp )],
    error    => [qw( chomp )],
};

$test_env->prepare_fixture(
    sub {
        MT::Test->init_db;

        # Content Type
        my $ct1 = MT::Test::Permission->make_content_type(
            name    => 'test content type 1',
            blog_id => $blog_id,
        );
        my $cf_single_line_text = MT::Test::Permission->make_content_field(
            blog_id         => $ct1->blog_id,
            content_type_id => $ct1->id,
            name            => 'single line text',
            type            => 'single_line_text',
        );
        my $fields = [
            {   id        => $cf_single_line_text->id,
                order     => 1,
                type      => $cf_single_line_text->type,
                options   => { label => $cf_single_line_text->name },
                unique_id => $cf_single_line_text->unique_id,
            },
        ];
        $ct1->fields($fields);
        $ct1->save or die $ct1->errstr;

        # Content Data
        MT::Test::Permission->make_content_data(
            blog_id         => $blog_id,
            content_type_id => $ct1->id,
            status          => MT::ContentStatus::RELEASE(),
            data            => {
                $cf_single_line_text->id => 'test single line text ' . $_,
            },
        ) for ( 1 .. 5 );
    }
);

my $ct1 = MT::ContentType->load( { name => 'test content type 1' } );

$vars->{ct1_id}  = $ct1->id;
$vars->{ct1_uid} = $ct1->unique_id;

MT::Test::Tag->run_perl_tests($blog_id);

# MT::Test::Tag->run_php_tests($blog_id);

__END__

=== MT::Contents without modifier
--- template
<mt:Contents>a</mt:Contents>
--- expected
aaaaa

=== MT::Contents
--- template
<mt:Contents blog_id="1" name="test content type 1">a</mt:Contents>
--- expected
aaaaa

=== MT::Contents with content_type_id modifier
--- template
<mt:Contents content_type_id="[% ct1_id %]">a</mt:Contents>
--- expected
aaaaa

=== MT::Contents with ct_unique_id modifier
--- SKIP
--- template
<mt:Contents ct_unique_id="[% ct1_uid %]">a</mt:Contents>
--- expected
aaaaa

=== MT::Contents with name modifier
--- template
<mt:Contents name="test content type 1">a</mt:Contents>
--- expected
aaaaa

=== MT::Contents with name modifier and wrong blog_id
--- template
<mt:Contents name="test content type 1" blog_ids="2">a</mt:Contents>
--- error
No Content Type could be found.

=== MT::ContentsCount with limit
--- template
<mt:Contents blog_id="1" name="test content type 1" limit="3">a</mt:Contents>
--- expected
aaa

=== MT::ContentsCount with sort_by content field
--- template
<mt:Contents blog_id="1" name="test content type 1" sort_by="field:single line text">
<mt:ContentFields><mt:ContentField><mt:ContentFieldValue></mt:ContentField></mt:ContentFields>
</mt:Contents>
--- expected
test single line text 5

test single line text 4

test single line text 3

test single line text 2

test single line text 1

