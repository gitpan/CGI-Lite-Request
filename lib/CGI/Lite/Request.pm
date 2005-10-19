package CGI::Lite::Request;

use CGI::Lite::Cookie;
use CGI::Lite::Upload;

use File::Type;
use HTTP::Headers;
use URI;

use base qw(CGI::Lite);

our $VERSION = '0.01';

=head1 NAME

CGI::Lite::Request - Request object based on CGI::Lite

=head1 SYNOPSIS

  use CGI::Lite::Request;
   
  my $req = CGI::Lite::Request->new;
  my $req = CGI::Lite::Request->instance;
   
  $foo  = $req->param('foo');
  @foos = $req->param('foo');                   # multiple values
  @params = $req->params();                     # params in parse order
  $foo  = $req->args->{foo};                    # hash ref
  %args = $req->args;                           # hash
  $uri = $req->uri;                             # $ENV{SCRIPT_NAME}/$ENV{PATH_INFO}
  $req->print(@out);                            # print to STDOUT
  $req->headers;                                # HTTP::Headers instance
  $req->send_http_header;                       # print the header
  $req->send_cgi_header(@fields};               # prints a raw header
  $req->content_type('text/html');              # set
  $req->content_type;                           # get
  $path = $req->path_info;                      # $ENV{PATH_INFO}
  $cookie = $req->cookie('my_cookie');          # fetch or create a cookie
  $req->cookie('SID')->value($sessid);          # set a cookie
  $upload = $req->upload('my_field');           # CGI::Lite::Upload instance
  $uploads = $req->uploads;                     # hash ref of CGI::Lite::Upload objects

=head1 DESCRIPTION

This module extends L<CGI::Lite> to provide an interface which is compatible with the most commonly used
methods of L<Apache::Request> as a fat free alternative to L<CGI>. All methods of L<CGI::Lite> are inherited
as is, and the following are defined herein:

=head1 METHODS

=over

=item instance

Allows L<CGI::Lite::Request> to behave as a singleton.

=cut

our %_instances = ();

sub instance { $_instances{$$} ? $_instances{$$} : $_[0]->new }

=item new

Constructor

=cut

sub new {
    my $class = shift;
    $self = $class->SUPER::new();

    if ($^O eq 'darwin') {
        $self->set_platform('Mac');
    }
    elsif ($^O eq 'MSWin32') {
        $self->set_platform('Windows');
    }
    else {
        $self->set_platform('Unix');
    }

    $_instances{$$} = $self;

    bless $self, $class;
    $self->parse(); # FIXME - error checking here

    $self->{_headers} = HTTP::Headers->new(
        Status            => '200 OK',
        Content_Type      => 'text/html',
        Pragma            => 'no-cache',
        Cache_Control     => 'no-cache',
        Connection        => 'close',
    );
 
    $self->{_cookies} = CGI::Lite::Cookie->fetch;

    return $self;
}

=item headers

accessor to an internally kept L<HTTP::Headers> object.

=cut

sub headers { $_[0]->{_headers} }

sub content_encoding { shift->headers->content_encoding(@_) }
sub content_length   { shift->headers->content_length(@_)   }
sub content_type     { shift->headers->content_type(@_)     }
sub header           { shift->headers->header(@_)           }

sub method     { $ENV{REQUEST_METHOD} }
sub referer    { $ENV{HTTP_REFERER    }
sub address    { $ENV{REMOTE_ADDR}    }
sub hostname   { $ENV{REMOTE_HOST}    }
sub protocol   { $ENV{SERVER_PROTOCOL}}
sub user       { $ENV{REMOTE_USER}    }
sub user_agent { $ENV{HTTP_USER_AGENT }

=item parse

parses the incoming request - this is called automatically from the
constructor, so you shouldn't need to call this expicitly.

=cut

sub parse {
    my $self = shift;
    undef($self->{$_}) for qw[
        _base
        _secure
        _headers
        _cookies
        _path_info
    ];
    $self->{_uploads} = { };
    $self->set_file_type('handle');
    $self->parse_new_form_data(@_);
}

=item args

return the request parameters as a hash or hash reference depending on
the context. All form data, query string and cookie parameters are available
in the returned hash(ref)

=cut

sub args {
    my $self = shift;
    wantarray ? %{$self->{web_data}} : $self->{web_data};
}

=item param( $key )

get a named parameter. If called in a scalar context, and if more than one
value exists for a field name in the incoming form data, then an array reference
is returned, otherwise for multiple values, if called in a list context, then
an array is returned. If the value is a simple scalar, then in a scalar context
just that value is returned.

=cut

sub param {
    my $self = shift;
    my $key  = shift;
    if (wantarray and ref $self->args->{$key} eq 'ARRAY') {
        return @{$self->args->{$key}};
    } else {
        return $self->args->{$key};
    }
}

=item params

returns all the parameters in the order in which they were parsed. Also includes
cookies and query string parameters.

=cut

sub params {
    my $self = shift;
    return @{$self->{web_data}}{$self->get_ordered_keys};
}

=item uri

returns the url minus the query string

=cut

sub uri {
    my ($self) = @_;
    return join('', $self->base, $self->path_info);
}

=item secure

returns true if the request came over https

=cut

sub secure {
    my $self = shift;
    unless (defined $self->{_secure}) {
        if ( $ENV{HTTPS} && uc( $ENV{HTTPS} ) eq 'ON' ) {
            $self->{_secure}++;
        }

        if ( $ENV{SERVER_PORT} == 443 ) {
            $self->{_secure}++;
        }
    }
    $self->{_secure};
}

sub base {
    my $self = shift;
    unless ($self->{_base}) {
        my $base;
        my $scheme = $self->secure ? 'https' : 'http';
        my $host   = $ENV{HTTP_HOST}   || $ENV{SERVER_NAME};
        my $port   = $ENV{SERVER_PORT} || 80;
        my $path   = $ENV{SCRIPT_NAME} || '/';

        unless ( $path =~ /\/$/ ) {
            $path .= '/';
        }

        $base = URI->new;
        $base->scheme($scheme);
        $base->host($host);
        $base->port($port);
        $base->path($path);

        $self->{_base} = $base->canonical->as_string;
    }
    $self->{_base};
}

=item path_info

accessor to the part of the url after the script name

=cut

sub path_info {
    my $self = shift;
    unless ($self->{_path_info}) {
        my $path = $ENV{PATH_INFO} || '/';
        my $location = $ENV{SCRIPT_NAME} || '/';
        $path =~ s/^($location)?\///;
        $path =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
        $path =~ s/^\///;
        $self->{_path_info} = $path;
    }
    $self->{_path_info};
}

=item print

print to respond to the request. This is normally done after
C<send_http_header> to print the body of data which should be
sent back the the user agent

=cut

sub print {
    my $self = shift;
    CORE::print(@_);
}

=item send_http_header

combines the response headers and sends these to the user agent

=cut

sub send_http_header {
    my $self = shift;
    if (my $content_type = shift) {
        $self->content_type($content_type);
    }
    unless ($self->content_type) {
        $self->content_type('text/html');
    }
    $self->headers->header(
        Set_Cookie => join(
            "\n", map {
                $_->as_string
            } values %{$self->cookies}
        )
    );

    $self->print($self->headers->as_string, "\015\012" x 2);
}

=item cookie

returnes a named L<CGI::Lite::Cookie> object. If one doesn't
exist by the passed name, then creates a new one and returns
it. Typical semantics would be:

    $sessid = $req->cookie('SID')->value;
    $req->cookie('SID')->value($sessid);

both of these methods will create a new L<CGI::Lite::Cookie>
object if one named 'SID' doesn't already exist. If you don't
want this behaviour, see C<cookies> method

=cut

sub cookie {
    my ($self, $name) = @_;
    $self->{_cookies}->{$name} ||= CGI::Lite::Cookie->new(
        -name  => $name,
        -value => '',
    );
    return $self->{_cookies}->{$name};
}

=item cookies

returns a hash reference of L<CGI::Lite::Cookie> objects keyed on their names.
This can be used for accessing cookies where you don't want them
to be created automatically if they don't exists, or for simply
checking for their existence:

    if (exists $req->cookies->{'SID'}) {
        $sessid = $req->cookies->{'SID'}->value;
    }

see L<CGI::Lite::Cookie> for more details

=cut

sub cookies { $_[0]->{_cookies} }

=item upload

returns a named L<CGI::Lite::Upload> object keyed on the field name
with which it was associated when uploaded.

=cut

sub upload {
    my ($self, $filename) = @_;
    return $self->uploads->{$filename};
}

=item uploads

returns a hash reference of all the L<CGI::Lite::Upload> objects
keyed on their names.

see L<CGI::Lite::Upload> for details

=cut

sub uploads { $_[0]->{_uploads} }

sub _create_handles {
    my ($self, $files) = @_;

    my $ft = File::Type->new;
    my ($upload, $name, $path);
    while (($name, $path) = each %$files) {
        $upload = CGI::Lite::Upload->new;
        $upload->tempname($path);
        $upload->filename($name);
        $upload->type($ft->mime_type($path));
        $upload->size(-s $path);
        $self->{_uploads}->{$name} = $upload;
    }
}

1;

=head1 AUTHOR

Richard Hundt <richard NO SPAM AT protea-systems.com>

=head1 SEE ALSO

L<CGI::Lite>, L<CGI::Lite::Cookie>, L<CGI::Lite::Upload>

=head1 LICENCE

This library is free software and may be used under the same terms as Perl itself

=cut
