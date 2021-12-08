# This code is part of distribution HTML::Inspect.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

package HTML::Inspect;

use strict;
use warnings;
use utf8;

use Log::Report 'html-inspect';

use HTML::Inspect::Util       qw(trim_attr xpc_find get_attributes absolute_url);
use HTML::Inspect::Normalize  qw(set_page_base);

use HTML::Inspect::Links      ();    # mixin for collectLink*()
use HTML::Inspect::OpenGraph  ();    # mixin for collectOpenGraph()
use HTML::Inspect::Meta       ();    # mixin for collectMeta*()
use HTML::Inspect::References ();    # mixin for collectRef*()

use XML::LibXML ();
use Scalar::Util qw(blessed);
use URI ();

=encoding utf-8

=chapter NAME

HTML::Inspect - Inspect a HTML document

=chapter SYNOPSIS

    my $source    = 'http://example.com/doc';
    my $inspector = HTML::Inspect->new(
        location => $source,
        html_ref => \$html,
    );
    my $classic   = $inspector->collectMetaClassic;

=chapter DESCRIPTION

This module extracts information from HTML, using a clean parser (L<XML::LibXML>)
Returned structures may need further processing.  Please suggest additional
extractors.

This module is part of the "Crawl Pipeline".  You can find a B<detailed description>
of each of the output of the methods below on its web-page at
F<https://pipeline.shared-search.eu/extract/>

B<URL normalization> is a really crucial feature of the output of these methods.
You can use this separately via functions in L<HTML::Inspect::Normalization>.

=chapter METHODS

=section Constructors

=c_method new %options

=requires html_ref REF-String
References to a (possibly troublesome) HTML string.  Passed as reference
to avoid copying large strings.

=requires location URL
An absolute url as a string or L<URI> instance, which explains where the
HTML was found.  It is used as base of relative URLs found in the HTML,
unless it contains as C<< <base> >> element.

=cut

sub new {
    my $class = shift;
    (bless {}, $class)->_init( {@_} );
}

my $find_base_href = xpc_find '//base[@href][1]';
sub _init($) {
    my ($self, $args) = @_;

    my $html_ref = $args->{html_ref} or panic "html_ref is required";
    ref $html_ref eq 'SCALAR'        or panic "html_ref not SCALAR";
    $$html_ref =~ m!\<\s*/?\s*\w+!   or error "Not HTML: '" . substr($$html_ref, 0, 20) . "'";

    my $req = $args->{location}      or panic '"location" is mandatory';
    my $loc = $self->{HI_location} = blessed $req ? $req : URI->new($req);

    my $dom = XML::LibXML->load_html(
        string            => $html_ref,
        recover           => 2,
        suppress_errors   => 1,
        suppress_warnings => 1,
        no_network        => 1,
        no_xinclude_nodes => 1,
    );

    my $doc = $self->{HI_doc} = $dom->documentElement;
    $self->{HI_xpc} = XML::LibXML::XPathContext->new($doc);

    ### Establish the base for relative links.

    my ($base, $rc, $err);
    if(my ($base_elem) = $find_base_href->($self)) {
        ($base, $rc, $err) = set_page_base $base_elem->getAttribute('href');
        unless($base) {
            warning __x"Illegal base href '{href}' in {url}: {err}",
                href => $base_elem->getAttribute('href'), url => $loc, err => $err;
        }
    }
    else {
        my ($base, $rc, $err) = set_page_base $loc->as_string;
        unless($base) {
            warning __x"Illegal page location '{url}': {err}", url => $loc, err => $err;
            return ();
        }
    }
    $self->{HI_base} = URI->new($base);   # base needed for other protocols (ftp)

    $self;
}

#-------------------------

=chapter Accessors

=method location

The L<URI> object which represents the C<location> parameter
which was passed as default base for relative links to C<new()>.

=cut

sub location() { $_[0]->{HI_location} }

=method base

The base URI, which is used for relative links in the page.  This is the
C<location>, unless the HTML contains a C<< <base href> >> declaration.
The base URI is a string representation, in absolute and normalized form.

=cut

sub base() { $_[0]->{HI_base} }

# The root XML::LibXML::Element of the current document.
sub _doc() { $_[0]->{HI_doc} }

# Returns the XPathContext for the current document.  Used via ::Util::xpc_find
sub _xpc() { $_[0]->{HI_xpc} }

#-------------------------

=chapter Collecting

=section The E<lt>linkE<gt> element

=method collectLinks 

Collect all C<< <link> >> relations from the document.  The returned HASH
contains the relation (the C<rel> attribute, required) to an ARRAY of
link elements with that value.  The ARRAY elements are HASHes of all
attributes of the link and and all lower-cased.  The added C<href_uri>
key will be a normalized, absolute translation of the C<href> attribute.
=cut

# All collectLinks* in the ::Links.pm mixin

=section The E<lt>metaE<gt> element

=method collectMetaClassic %options

Returns a HASH reference with all C<< <meta> >> information of traditional content:
the single C<charset> and all C<http-equiv> records, plus the subset of names which
are listed on F<https://www.w3schools.com/tags/tag_meta.asp>.  People defined far too
many names to be useful for everyone.

=example

    {  'http-equiv' => { 'content-type' => 'text/plain' },
        charset => 'UTF-8',
        name => { author => 'John Smith' , description => 'The John Smith\'s page.'},
    }


=method collectMetaNames %options

Returns a HASH with all C<< <meta> >> records which have both a C<name> and a
C<content> attribute.  These are used as key-value pairs for many, many different
purposes.

=example

   { author => 'John Smith' , description => 'The John Smith\'s page.'}


=method collectMeta %options

Returns an ARRAY of B<all> kinds of C<< <meta> >> records, which have a wide
variety of fields and may be order dependend!!!

=example

   [ { http-equiv => 'Content-Type', content => 'text/html; charset=UTF-8' },
     { name => 'viewport', content => 'width=device-width, initial-scale=1.0' },
   ]

=cut

# All collectMeta* in ::Meta.pm mixin

=section References

The amount of references is large (easily a few hundred per HTML page),
so you may wat to specify a filter.
The C<%filter> rules will produce a subset of the links found.  You can
use: C<http_only> (returning only http and https links), C<mailto_only>,
C<maximum_set> (returning only the first C<n> links) and C<matching>,
returning links matching a certain regex.

=method collectReferencesFor $tag, $attr, %filter

Returns an ARRAY of unique normalized URIs, which where found with the
C<$tag> attribute C<$attr>.  For instance, tag C<image> attribute C<src>.
The URIs are in their textual order in the document, where only the
first encounter is recorded.

=method collectReferences %filter

Collects all references from document.  Method C<collectReferencesFor()>
is called for a list of known tag/attribute pairs, and returned as a
HASH of ARRAYs.  The keys of the HASH have format "$tag_$attribute".
=cut

### collectReferences*() are in mixin file ::References

=section Other

=method collectOpenGraph
Returns structured OpenGraph information, when available in the HTML.

The logic really understands OpenGraph, and simplifies access to it:
facts which may appear multiple times will always be returned as ARRAY.
=cut

### collectOpenGraph() is in mixin file ::OpenGraph

=chapter SEE ALSO

L<XML::LibXML>, L<Log::Report>

This software is a component of the Crawl Pipeline,
F<https://pipeline.shared-search.eu>.
Development was made possible with a generous gift by the NLnet Foundation.

=chapter AUTHORS and COPYRIGHT
    
    Mark Overmeer
    CPAN ID: MARKOV
    markov at cpan dot org

    Красимир Беров
    CPAN ID: BEROV
    berov на cpan точка org
    https://studio-berov.eu

This is free software, licensed under: The Artistic License 2.0 (GPL
Compatible) The full text of the license can be found in the LICENSE
file included with this module.
=cut

1;
