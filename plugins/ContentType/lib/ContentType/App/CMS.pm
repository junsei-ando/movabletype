# Movable Type (r) (C) 2007-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package ContentType::App::CMS;

use strict;
use warnings;

use JSON qw/ encode_json decode_json /;
use Digest::SHA1 qw/ sha1_hex /;
use Encode qw/ encode_utf8 /;

use MT;
use MT::Entity;
use MT::EntityIdx;
use MT::ContentType;
use MT::ContentTypeData;

{
    # TBD: Move to Core.

    no warnings 'redefine';

    *MT::Author::can_manage_content_types = sub {
        my $author = shift;
        return $author->is_superuser(@_);
        }
}

sub init_request {
    my ( $cb, $app ) = @_;

    my @content_types = MT::ContentType->load();
    foreach my $content_type (@content_types) {
        $app->add_callback(
            'cms_pre_load_filtered_list.content_type_data_'
                . $content_type->id,
            0, $app, \&cms_pre_load_filtered_list
        );
    }
    return 1;
}

sub tmpl_param_edit_role {
    my ( $cb, $app, $param, $tmpl ) = @_;
    $param->{content_type_perm_groups} = MT::ContentType->permission_groups;
}

sub cfg_content_type {
    my ( $app, $param ) = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;

    require MT::Promise;
    my $content_type_id = $q->param('id');
    my $obj_promise     = MT::Promise::delay(
        sub {
            return undef unless $content_type_id;
            return MT::ContentType->load( { id => $content_type_id } )
                || undef;
        }
    );

    my $content_type = $obj_promise->force();
    if ($content_type) {
        $param->{name}       = $content_type->name;
        $param->{unique_key} = $content_type->unique_key;
        my $json = $content_type->entities;
        my $array = $json ? JSON::decode_json($json) : [];
        @$array = map {
            $_->{entity_id} = $_->{id};
            delete $_->{id};
            $_;
        } @$array;
        @$array = sort { $a->{order} <=> $b->{order} } @$array;
        $param->{entities} = $array;
    }

    foreach my $name (qw( saved err_msg id name )) {
        $param->{$name} = $q->param($name) if $q->param($name);
    }
    $app->build_page( $plugin->load_tmpl('cfg_content_type.tmpl'), $param );
}

sub save_cfg_content_type {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    $app->validate_magic
        or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my $content_type_id = $q->param('id');
    my $name            = $q->param('name');
    my $edited          = $q->param('edited');

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                id      => $content_type_id,
                err_msg => $plugin->translate(
                    "Name \"[_1]\" is already used.", $name
                ),
            }
        )
    ) if !$content_type_id && MT::ContentType->count( { name => $name } );

    my $content_type
        = $content_type_id
        ? MT::ContentType->load($content_type_id)
        : MT::ContentType->new();

    $content_type->blog_id($blog_id);
    $content_type->name($name);

    my $json = $content_type->entities();
    my $entities = $json ? JSON::decode_json($json) : [];
    @$entities = map {
        $_->{order} = $q->param( 'order-' . $_->{id} );
        $_->{label} = $q->param('content-label') == $_->{id} ? 1 : 0;
        $_;
    } @$entities;
    $content_type->entities( JSON::encode_json($entities) );

    my $unique_key
        = defined $content_type->unique_key && $content_type->unique_key
        ? $content_type->unique_key
        : _generate_unique_key($name);
    $content_type->unique_key($unique_key)
        unless $content_type->unique_key;

    $content_type->save
        or return $app->error(
        $plugin->translate(
            "Saving content type failed: [_1]",
            $content_type->errstr
        )
        );

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type->id,
                saved   => 1,
            }
        )
    );
}

sub cfg_entity {
    my ( $app, $param ) = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;

    my $blog_id                 = $q->param('blog_id');
    my $entity_id               = $q->param('id');
    my $entity_type             = $q->param('type') || '';
    my $related_content_type_id = $q->param('related_content_type_id') || '';

    require MT::Promise;
    my $obj_promise = MT::Promise::delay(
        sub {
            return undef unless $entity_id;
            return MT::Entity->load( { id => $entity_id } )
                || undef;
        }
    );

    my $entity = $obj_promise->force();
    if ($entity) {
        $param->{name}                    = $entity->name;
        $param->{type}                    = $entity->type;
        $param->{default}                 = $entity->default;
        $param->{options}                 = $entity->options;
        $param->{related_content_type_id} = $entity->related_content_type_id;
        $param->{unique_key}              = $entity->unique_key;
        $entity_type                      = $entity->type;
        $related_content_type_id          = $entity->related_content_type_id;
    }

    my $entity_types = $app->registry('entity_types');
    my @e_array      = map {
        my $hash = {};
        $hash->{type}     = $_;
        $hash->{label}    = $entity_types->{$_}{label};
        $hash->{order}    = $entity_types->{$_}{order};
        $hash->{selected} = $_ eq $entity_type ? 1 : 0;
        $hash;
    } keys %$entity_types;
    @e_array = sort { $a->{order} <=> $b->{order} } @e_array;
    $param->{entity_types} = \@e_array;

    my @content_types = MT::ContentType->load( { blog_id => $blog_id } );
    my @c_array = map {
        my $hash = {};
        $hash->{id}       = $_->id;
        $hash->{name}     = $_->name;
        $hash->{selected} = $_->id == $related_content_type_id ? 1 : 0;
        $hash;
    } @content_types;
    $param->{content_types} = \@c_array;

    foreach my $name (
        qw( saved err_msg content_type_id id name type default options ))
    {
        $param->{$name} = $q->param($name) if $q->param($name);
    }
    $app->build_page( $plugin->load_tmpl('cfg_entity.tmpl'), $param );
}

sub save_cfg_entity {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    $app->validate_magic
        or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");
    my $content_type_id = scalar $q->param('content_type_id')
        or return $app->errtrans("Invalid request.");

    my $entity_id               = $q->param('id');
    my $name                    = $q->param('name');
    my $type                    = $q->param('type');
    my $default                 = $q->param('default');
    my $options                 = $q->param('options');
    my $related_content_type_id = $q->param('related_content_type_id');

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_entity',
            args   => {
                blog_id         => $blog_id,
                content_type_id => $content_type_id,
                id              => $entity_id,
                err_msg         => $plugin->translate(
                    "Name \"[_1]\" is already used.", $name
                ),
                name                    => $name,
                type                    => $type,
                default                 => $default,
                options                 => $options,
                related_content_type_id => $related_content_type_id,
            }
        )
        )
        if !$entity_id
        && MT::Entity->count(
        { content_type_id => $content_type_id, name => $name } );

    my $entity
        = $entity_id
        ? MT::Entity->load($entity_id)
        : MT::Entity->new();

    $entity->blog_id($blog_id);
    $entity->content_type_id($content_type_id);
    $entity->name($name);
    $entity->type($type);
    $entity->options($options);
    $entity->related_content_type_id( $related_content_type_id || 0 );

    my $unique_key
        = defined $entity->unique_key && $entity->unique_key
        ? $entity->unique_key
        : _generate_unique_key($name);
    $entity->unique_key($unique_key)
        unless $entity->unique_key;

    $entity->save
        or return $app->error(
        $plugin->translate( "Saving entity failed: [_1]", $entity->errstr ) );

    my $content_type = MT::ContentType->load($content_type_id);
    my $json         = $content_type->entities();
    my $entities     = $json ? JSON::decode_json($json) : [];
    if ( grep { $_->{id} == $entity->id } @$entities ) {
        @$entities = map {
            if ( $_->{id} == $entity->id ) {
                $_->{name} = $name;
                $_->{type} = $type;
            }
            $_;
        } @$entities;
    }
    else {
        push @$entities,
            {
            id         => $entity->id,
            name       => $name,
            type       => $type,
            order      => scalar(@$entities) + 1,
            label      => ( scalar(@$entities) ? 0 : 1 ),
            unique_key => $entity->unique_key,
            };
    }
    $content_type->entities( JSON::encode_json($entities) );

    $content_type->save
        or return $app->error(
        $plugin->translate(
            "Saving content type failed: [_1]",
            $content_type->errstr
        )
        );

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_entity',
            args   => {
                blog_id         => $blog_id,
                content_type_id => $content_type_id,
                id              => $entity->id,
                saved           => 1,
            }
        )
    );
}

sub delete_entity {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    #$app->validate_magic
    #    or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");
    my $content_type_id = scalar $q->param('content_type_id')
        or return $app->errtrans("Invalid request.");
    my $entity_id = scalar $q->param('id')
        or return $app->errtrans("Invalid request.");

    my $entity = MT::Entity->load($entity_id);
    $entity->remove()
        or return $app->error(
        $plugin->translate( "Remove entity failed: [_1]", $entity->errstr ) );

    my $content_type = MT::ContentType->load($content_type_id);
    my $json         = $content_type->entities();
    my $entities     = JSON::decode_json($json);
    @$entities = grep { $_->{id} ne $entity_id } @$entities;
    $content_type->entities( JSON::encode_json($entities) );

    $content_type->save
        or return $app->error(
        $plugin->translate(
            "Saving content type failed: [_1]",
            $content_type->errstr
        )
        );

    return $app->redirect(
        $app->uri(
            'mode' => 'cfg_content_type',
            args   => {
                blog_id => $blog_id,
                id      => $content_type_id,
                saved   => 1,
            }
        )
    );
}

sub select_list_content_type {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my @content_types = MT::ContentType->load( { blog_id => $blog_id } );
    $param->{content_types} = \@content_types;

    $app->build_page( $plugin->load_tmpl('select_list_content_type.tmpl'),
        $param );
}

sub select_edit_content_type {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");

    my @content_types = MT::ContentType->load( { blog_id => $blog_id } );
    my @array;
    foreach my $content_type (@content_types) {
        my $hash = {};
        $hash->{id}      = $content_type->id;
        $hash->{blog_id} = $content_type->blog_id;
        $hash->{name}    = $content_type->name;
        my $unique_key = $content_type->unique_key;
        $hash->{can_edit} = 1
            if $app->permissions->can_do(
            'manage_content_type:' . $unique_key );
        push @array, $hash;
    }
    $param->{content_types} = \@array;

    $app->build_page( $plugin->load_tmpl('select_edit_content_type.tmpl'),
        $param );
}

sub edit_content_type_data {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");
    my $content_type_id = scalar $q->param('content_type_id')
        or return $app->errtrans("Invalid request.");

    my $content_type = MT::ContentType->load($content_type_id);

    $param->{name} = $content_type->name;

    my $json                 = $content_type->entities;
    my $array                = $json ? JSON::decode_json($json) : [];
    my $ct_unique_key        = $content_type->unique_key;
    my $content_type_data_id = scalar $q->param('id');

    my $data;
    if ($content_type_data_id) {
        my $content_type_data
            = MT::ContentTypeData->load($content_type_data_id);
        my $json = $content_type_data->data;
        $data = $json ? JSON::decode_json($json) : [];
    }

    my $entity_types = $app->registry('entity_types');
    @$array = map {
        my $e_unique_key = $_->{unique_key};
        $_->{can_edit} = 1
            if $app->permissions->can_do(
            'content_type:' . $ct_unique_key . '-entity:' . $e_unique_key );
        $_->{entity_id} = $_->{id};
        delete $_->{id};

        $_->{value}
            = $q->param( $_->{entity_id} ) ? $q->param( $_->{entity_id} )
            : $content_type_data_id        ? $data->{ $_->{entity_id} }
            :                                '';

        my $entity_type = $entity_types->{ $_->{type} };
        if ( my $html = $entity_type->{html} ) {
            if ( !ref $html ) {
                $html = MT->handler_to_coderef($html);
            }
            if ( 'CODE' eq ref $html ) {
                $_->{html} = $html->( $app, $_->{entity_id}, $_->{value} );
            }
            else {
                $_->{html} = $html;
            }
        }
        $_->{type} = $entity_types->{ $_->{type} }{type};

        $_;
    } @$array;

    $param->{entities} = $array;

    foreach my $name (qw( saved err_msg content_type_id id )) {
        $param->{$name} = $q->param($name) if $q->param($name);
    }
    $app->build_page( $plugin->load_tmpl('edit_content_type_data.tmpl'),
        $param );
}

sub save_content_type_data {
    my ($app)  = @_;
    my $q      = $app->param;
    my $plugin = $app->component("ContentType");
    my $cfg    = $app->config;
    my $param  = {};

    $app->validate_magic
        or return $app->errtrans("Invalid request.");
    my $perms = $app->permissions;
    return $app->permission_denied()
        unless $app->user->is_superuser()
        || ( $perms
        && $perms->can_administer_blog );

    my $blog_id = scalar $q->param('blog_id')
        or return $app->errtrans("Invalid request.");
    my $content_type_id = scalar $q->param('content_type_id')
        or return $app->errtrans("Invalid request.");

    my $content_type = MT::ContentType->load($content_type_id);
    my $json         = $content_type->entities;
    my $entities     = $json ? JSON::decode_json($json) : [];

    my $content_type_data_id = scalar $q->param('id');

    my $entity_types = $app->registry('entity_types');

    my $data = {};
    foreach my $entity (@$entities) {
        my $entity_type = $entity_types->{ $entity->{type} };
        $data->{ $entity->{id} }
            = _get_form_data( $app, $entity_type, $entity->{id} );
    }
    foreach my $entity (@$entities) {
        my $entity_type = $entity_types->{ $entity->{type} };
        my $param_name  = 'entity-' . $entity->{id};
        if ( my $validate = $entity_type->{validate} ) {
            if ( !ref $validate ) {
                $validate = MT->handler_to_coderef($validate);
            }
            if ( 'CODE' eq ref $validate ) {
                $app->error(undef);
                my $result = $validate->( $app, $entity->{id} );
                if ( my $err = $app->errstr ) {
                    $data->{blog_id}         = $blog_id;
                    $data->{content_type_id} = $content_type_id;
                    $data->{id}              = $content_type_data_id;
                    $data->{err_msg}         = $err;
                    return $app->redirect(
                        $app->uri(
                            'mode' => 'edit_content_type_data',
                            args   => $data,
                        )
                    );
                }
            }
        }
    }
    $data = JSON::encode_json($data);

    my $content_type_data
        = $content_type_data_id
        ? MT::ContentTypeData->load($content_type_data_id)
        : MT::ContentTypeData->new();

    $content_type_data->blog_id($blog_id);
    $content_type_data->content_type_id($content_type_id);
    $content_type_data->data($data);
    $content_type_data->save
        or return $app->error(
        $plugin->translate(
            "Saving [_1] failed: [_2]", $content_type->name,
            $content_type_data->errstr
        )
        );

    foreach my $entity (@$entities) {
        my $entity_type = $entity_types->{ $entity->{type} };
        my $value = _get_form_data( $app, $entity_type, $entity->{id} );

        my $entity_idx
            = $content_type_data_id
            ? MT::EntityIdx->load(
            {   content_type_id      => $content_type_id,
                content_type_data_id => $content_type_data->id,
                entity_id            => $entity->{id},
            }
            )
            : MT::EntityIdx->new();
        $entity_idx = MT::EntityIdx->new() unless $entity_idx;
        $entity_idx->content_type_id($content_type_id);
        $entity_idx->content_type_data_id( $content_type_data->id );

        my $type = $entity_types->{ $entity->{type} }{type};
        if ( $type eq 'varchar' ) {
            $entity_idx->value_varchar($value);
        }
        elsif ( $type eq 'varchar' ) {
            $entity_idx->value_text($value);
        }
        elsif ( $type eq 'datetime' ) {
            $entity_idx->value_datetime($value);
        }
        elsif ( $type eq 'integer' ) {
            $entity_idx->value_integer($value);
        }
        elsif ( $type eq 'float' ) {
            $entity_idx->value_float($value);
        }

        $entity_idx->entity_id( $entity->{id} );
        $entity_idx->save
            or return $app->error(
            $plugin->translate(
                "Saving entity index failed: [_1]",
                $entity_idx->errstr
            )
            );
    }

    return $app->redirect(
        $app->uri(
            'mode' => 'edit_content_type_data',
            args   => {
                blog_id         => $blog_id,
                content_type_id => $content_type_id,
                id              => $content_type_data->id,
                saved           => 1,
            }
        )
    );
}

sub cms_pre_load_filtered_list {
    my ( $cb, $app, $filter, $load_options, $cols ) = @_;
    my $object_ds = $filter->object_ds;
    $object_ds =~ /content_type_data_(\d+)/;
    my $content_type_id = $1;
    $load_options->{terms}{content_type_id} = $content_type_id;
}

sub _generate_unique_key {
    my $name = shift || 'base_name';
    my $key = join( $ENV{'REMOTE_ADDR'},
        $ENV{'HTTP_USER_AGENT'}, time, $$, rand(9999), encode_utf8($name) );

    return ( sha1_hex($key) );
}

sub _get_form_data {
    my ( $app, $entity_type, $id ) = @_;

    if ( my $get_data = $entity_type->{get_data} ) {
        if ( !ref $get_data ) {
            $get_data = MT->handler_to_coderef($get_data);
        }
        if ( 'CODE' eq ref $get_data ) {
            return $get_data->( $app, $id );
        }
        else {
            return $get_data;
        }
    }
    else {
        my $q = $app->param;
        return $q->param( 'entity-' . $id );
    }
}

1;
