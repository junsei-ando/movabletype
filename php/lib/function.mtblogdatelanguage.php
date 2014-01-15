<?php
# Movable Type (r) (C) 2001-2014 Six Apart, Ltd. All Rights Reserved.
# This code cannot be redistributed without permission from www.sixapart.com.
# For more information, consult your Movable Type license.
#
# $Id$

function smarty_function_mtblogdatelanguage($args, &$ctx) {
    $blog = $ctx->stash('blog');
    return normalize_language( $blog->blog_date_language, $args['locale'],
        $args['ietf'] );
}
?>
