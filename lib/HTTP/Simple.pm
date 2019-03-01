package HTTP::Simple;

use strict;
use warnings;
use Carp 'croak';
use Exporter 'import';
use File::Basename 'dirname';
use File::Temp;
use HTTP::Tiny;
use JSON::PP;

our $VERSION = '0.001';

our @EXPORT = qw(get head getprint getstore mirror postform postjson postfile
  is_info is_success is_redirect is_error is_client_error is_server_error);

our $UA = HTTP::Tiny->new(agent => "HTTP::Simple/$VERSION");
our $JSON = JSON::PP->new->utf8->canonical->allow_nonref->convert_blessed;

sub get {
  my ($url) = @_;
  my $res = $UA->get($url);
  return $res->{content} if $res->{success};
  croak $res->{content} if $res->{status} == 599;
  croak "$res->{status} $res->{reason}";
}

sub head {
  my ($url) = @_;
  my $res = $UA->head($url);
  return $res->{headers} if $res->{success};
  croak $res->{content} if $res->{status} == 599;
  croak "$res->{status} $res->{reason}";
}

sub getprint {
  my ($url) = @_;
  my $res = $UA->get($url, {data_callback => sub { print $_[0] }});
  croak $res->{content} if $res->{status} == 599;
  return $res->{status};
}

sub getstore {
  my ($url, $file) = @_;
  my $temp = File::Temp->new(DIR => dirname $file);
  my $res = $UA->get($url, {data_callback => sub { print {$temp} $_[0] }});
  croak $res->{content} if $res->{status} == 599;
  close $temp->filename or croak "Failed to close $temp: $!";
  rename $temp->filename, $file or croak "Failed to rename $temp to $file: $!";
  $temp->unlink_on_destroy(0);
  return $res->{status};
}

sub mirror {
  my ($url, $file) = @_;
  my $res = $UA->mirror($url, $file);
  croak $res->{content} if $res->{status} == 599;
  return $res->{status};
}

sub postform {
  my ($url, $form) = @_;
  my $res = $UA->post_form($url, $form);
  return $res->{content} if $res->{success};
  croak $res->{content} if $res->{status} == 599;
  croak "$res->{status} $res->{reason}";
}

sub postjson {
  my ($url, $data) = @_;
  my %options;
  $options{headers} = {'Content-Type' => 'application/json; charset=UTF-8'};
  $options{content} = $JSON->encode($data);
  my $res = $UA->post($url, \%options);
  return $res->{content} if $res->{success};
  croak $res->{content} if $res->{status} == 599;
  croak "$res->{status} $res->{reason}";
}

sub postfile {
  my ($url, $file, $content_type) = @_;
  open my $fh, '<:raw', $file or croak "Failed to open $file: $!";
  my %options;
  $options{headers} = {'Content-Type' => $content_type} if defined $content_type;
  $options{content} = sub { my $buffer; sysread $fh, $buffer, 131072; $buffer };
  my $res = $UA->post($url, \%options);
  return $res->{content} if $res->{success};
  croak $res->{content} if $res->{status} == 599;
  croak "$res->{status} $res->{reason}";
}

sub is_info         { !!($_[0] >= 100 && $_[0] < 200) }
sub is_success      { !!($_[0] >= 200 && $_[0] < 300) }
sub is_redirect     { !!($_[0] >= 300 && $_[0] < 400) }
sub is_error        { !!($_[0] >= 400 && $_[0] < 600) }
sub is_client_error { !!($_[0] >= 400 && $_[0] < 500) }
sub is_server_error { !!($_[0] >= 500 && $_[0] < 600) }

1;

=head1 NAME

HTTP::Simple - Simple procedural interface to HTTP::Tiny

=head1 SYNOPSIS

  perl -MHTTP::Simple -e'getprint(shift)' 'https://example.com'

  use HTTP::Simple;

  my $content = get 'https://example.com';

  if (mirror('https://example.com', '/path/to/file.html') == 304) { ... }

  if (is_success(getprint 'https://example.com')) { ... }

  postform('https://example.com', {foo => ['bar', 'baz']});

  postjson('https://example.com', [{bar => 'baz'}]);

  postfile('https://example.com', '/path/to/file.png');

=head1 DESCRIPTION

This module is a wrapper of L<HTTP::Tiny> that provides simplified functions
for performing HTTP requests in a similar manner to L<LWP::Simple>, but with
slightly more useful error handling. For full control of the request process,
use L<HTTP::Tiny> directly.

Note that L<IO::Socket::SSL> is required for HTTPS requests with L<HTTP::Tiny>.

The L<HTTP::Tiny> object used by these functions to make requests can be
accessed as C<$HTTP::Simple::UA> (for example, to configure the timeout, or
replace it with a compatible object like L<HTTP::Tinyish>).

=head1 FUNCTIONS

All functions are exported by default.

=head2 get

  my $contents = get($url);

Retrieves the document at the given URL with a GET request and returns it as a
string. Throws an exception on connection or HTTP errors.

=head2 head

  my $headers = head($url);

Retrieves the headers at the given URL with a HEAD request and returns them as
a hash reference. Header field names are normalized to lower case, and values
may be an array reference if the header is repeated. Throws an exception on
connection or HTTP errors.

=head2 getprint

  my $status = getprint($url);

Retrieves the document at the given URL with a GET request and prints it as it
is received. Returns the HTTP status code. Throws an exception on connection
errors.

=head2 getstore

  my $status = getstore($url, $path);

Retrieves the document at the given URL with a GET request and stores it to the
given file path. Returns the HTTP status code. Throws an exception on
connection or filesystem errors.

=head2 mirror

  my $status = mirror($url, $path);

Retrieves the document at the given URL with a GET request and mirrors it to
the given file path, using the C<If-Modified-Since> headers to short-circuit if
the file exists and is new enough, and the C<Last-Modified> header to set its
modification time. Returns the HTTP status code. Throws an exception on
connection or filesystem errors.

=head2 postform

  my $contents = postform($url, $form);

Sends a POST request to the given URL with the given hash or array reference of
form data serialized to C<application/x-www-form-urlencoded>. Returns the
response body as a string. Throws an exception on connection or HTTP errors.

=head2 postjson

  my $contents = postjson($url, $data);

Sends a POST request to the given URL with the given data structure encoded to
JSON. Returns the response body as a string. Throws an exception on connection
or HTTP errors.

The JSON encoder defaults to a L<JSON::PP> instance, and can be accessed as
C<$HTTP::Simple::JSON>.

=head2 postfile

  my $contents = postfile($url, $path);
  my $contents = postfile($url, $path, $content_type);

Sends a POST request to the given URL, streaming the contents of the given
file. The content type is passed as C<application/octet-stream> if not
specified. Returns the response body as a string. Throws an exception on
connection or HTTP errors.

=head2 is_info

  my $bool = is_info($status);

Returns true if the status code indicates an informational response (C<1xx>).

=head2 is_success

  my $bool = is_success($status);

Returns true if the status code indicates a successful response (C<2xx>).

=head2 is_redirect

  my $bool = is_redirect($status);

Returns true if the status code indicates a redirection response (C<3xx>).

=head2 is_error

  my $bool = is_error($status);

Returns true if the status code indicates an error response (C<4xx> or C<5xx>).

=head2 is_client_error

  my $bool = is_client_error($status);

Returns true if the status code indicates a client error response (C<4xx>).

=head2 is_server_error

  my $bool = is_server_error($status);

Returns true if the status code indicates a server error response (C<5xx>).

=head1 BUGS

Report any issues on the public bugtracker.

=head1 AUTHOR

Dan Book <dbook@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2019 by Dan Book.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=head1 SEE ALSO

L<LWP::Simple>, L<HTTP::Tinyish>, L<ojo>
