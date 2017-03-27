# Movable Type (r) (C) 2001-2017 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

package MT::ObjectCategory;

use strict;

use MT::Blog;
use base qw( MT::Object );

__PACKAGE__->install_properties(
    {   column_defs => {
            'id'                => 'integer not null auto_increment',
            'blog_id'           => 'integer',
            'object_id'         => 'integer not null',
            'object_datasource' => 'string(50) not null',
            'category_id'       => 'integer not null',
        },
        indexes => {
            object_id         => 1,
            category_id       => 1,
            object_datasource => 1,

            # For MTCategories
            blog_ds_tag =>
                { columns => [ 'blog_id', 'object_datasource', 'category_id' ], },

            # For category count
            blog_ds_obj_tag => {
                columns =>
                    [ 'blog_id', 'object_datasource', 'object_id', 'category_id' ],
            },
        },
        child_of    => 'MT::Blog',
        datasource  => 'objectcategory',
        primary_key => 'id',
        cacheable   => 0,
    }
);

sub class_label {
    MT->translate("Category Placement");
}

sub class_label_plural {
    MT->translate("Category Placements");
}

1;
__END__

=head1 NAME

MT::ObjectCategory

=head1 METHODS

=head2 MT::ObjectCategory->class_label

Returns the localized descriptive name for this class.

=head2 MT::ObjectCategory->class_label_plural

Returns the localized, plural descriptive name for this class.

=head1 AUTHOR & COPYRIGHT

Please see L<MT/AUTHOR & COPYRIGHT>.

=cut

