# This code is part of distribution HTML::Inspect.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

### This module handles various generic extractions of <meta> elements.

package HTML::Inspect;    # Mixin

use strict;
use warnings;
use utf8;

use Log::Report 'html-inspect';

use HTML::Inspect::Util qw(trim_attr xpc_find get_attributes);

my $find_link_rel = xpc_find '//link[@rel]';
sub collectLinks() {
    my $self = shift;

    return $self->{HI_links} if $self->{HI_links};
    my $base = $self->base;

    my %links;
    foreach my $link ($find_link_rel->($self)) {
        my $attrs = get_attributes $link;
        $attrs->{href} = absolute_url($attrs->{href}, $base)
            if exists $attrs->{href};

        push @{$links{delete $attrs->{rel}}}, $attrs;
    }

    $self->{HI_links} = \%links;
}

1;
