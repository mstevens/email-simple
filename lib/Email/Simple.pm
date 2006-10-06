package Email::Simple;

use 5.00503;
use strict;
use Carp ();

$Email::Simple::VERSION = '1.995';
$Email::Simple::GROUCHY = 0;

my $crlf = qr/\x0a\x0d|\x0d\x0a|\x0a|\x0d/;  # We are liberal in what we accept.

=head1 NAME

Email::Simple - Simple parsing of RFC2822 message format and headers

=head1 SYNOPSIS

    my $email = Email::Simple->new($text);

    my $from_header = $email->header("From");
    my @received = $email->header("Received");

    $email->header_set("From", 'Simon Cozens <simon@cpan.org>');

    my $old_body = $email->body;
    $email->body_set("Hello world\nSimon");

    print $email->as_string;

=head1 DESCRIPTION

C<Email::Simple> is the first deliverable of the "Perl Email Project."  The
Email:: namespace is a reaction against the complexity and increasing bugginess
of the C<Mail::*> modules.  In contrast, C<Email::*> modules are meant to be
simple to use and to maintain, pared to the bone, fast, minimal in their
external dependencies, and correct.

=head1 METHODS

Methods are deliberately kept to a minimum. This is meant to be simple.
No, I will not add method X. This is meant to be simple. Why doesn't it
have feature Y? Because it's meant to be simple.

=head2 new

Parse an email from a scalar containing an RFC2822 formatted message,
and return an object.

=cut

sub new {
  my ($class, $text) = @_;

  Carp::croak 'Unable to parse undefined message' if !defined $text;

  my ($head, $body, $mycrlf) = _split_head_from_body($text);

  my $self = bless { body => $body, mycrlf => $mycrlf } => $class;

  $self->__read_header($head);

  return $self;
}

sub _split_head_from_body {
  my $text = shift;

  # The body is simply a sequence of characters that
  # follows the header and is separated from the header by an empty
  # line (i.e., a line with nothing preceding the CRLF).
  #  - RFC 2822, section 2.1
  if ($text =~ /(.*?($crlf))\2(.*)/sm) {
    return ($1, ($3 || ''), $2);
  } else {  # The body is, of course, optional.
    return ($text, "", "\n");
  }
}

# Header fields are lines composed of a field name, followed by a colon (":"),
# followed by a field body, and terminated by CRLF.  A field name MUST be
# composed of printable US-ASCII characters (i.e., characters that have values
# between 33 and 126, inclusive), except colon.  A field body may be composed
# of any US-ASCII characters, except for CR and LF.

# However, a field body may contain CRLF when used in header "folding" and
# "unfolding" as described in section 2.2.3.

sub __headers_to_list {
  my ($self, $head) = @_;

  my @headers;

  for (split /$crlf/, $head) {
    if (s/^\s+// or not /^([^:]+):\s*(.*)/) {
      # This is a continuation line. We fold it onto the end of
      # the previous header.
      next if !@headers;  # Well, that sucks.  We're continuing nothing?

      $headers[-1][1] .= $headers[-1][1] ? " $_" : $_;
    } else {
      push @headers, [ $1, $2 ];
    }
  }

  return \@headers;
}

sub _read_headers {
  Carp::carp "Email::Simple::_read_headers is private and depricated";
  my ($head) = @_;  # ARG!  Why is this a function? -- rjbs
  my $dummy = bless {} => __PACKAGE__;
  $dummy->__read_header($head);
  my $h = $dummy->__head->{head};
  my $o = $dummy->__head->{order};
  return ($h, $o);
}

sub __read_header {
  my ($self, $head) = @_;

  my $headers = $self->__headers_to_list($head);

  $self->{_head}
    = Email::Simple::__Header->new($headers, { crlf => $self->{mycrlf} });
}

sub __head {
  my ($self) = @_;
  return $self->{_head} if $self->{_head};

  if ($self->{head} and $self->{order} and $self->{header_names}) {
    Carp::carp "Email::Simple subclass appears to have broken header behavior";
    my $head = bless {} => 'Email::Simple::__Header';
    $head->{$_} = $self->{$_} for qw(head order header_names mycrlf);
    return $self->{_head} = $head;
  }
}

=head2 header

  my @values = $email->header($header_name);
  my $first  = $email->header($header_name);

In list context, this returns every value for the named header.  In scalar
context, it returns the I<first> value for the named header.

=cut

sub header { $_[0]->__head->header($_[1]); }

=head2 header_set

    $email->header_set($field, $line1, $line2, ...);

Sets the header to contain the given data. If you pass multiple lines
in, you get multiple headers, and order is retained.

=cut

sub header_set { (shift)->__head->header_set(@_); }

=head2 header_names

    my @header_names = $email->header_names;

This method returns the list of header names currently in the email object.
These names can be passed to the C<header> method one-at-a-time to get header
values. You are guaranteed to get a set of headers that are unique. You are not
guaranteed to get the headers in any order at all.

For backwards compatibility, this method can also be called as B<headers>.

=cut

sub header_names { $_[0]->__head->header_names }
BEGIN { *headers = \&header_names; }

=head2 header_pairs

  my @headers = $email->header_pairs;

This method returns a list of pairs describing the contents of the header.
Every other value, starting with and including zeroth, is a header name and the
value following it is the header value.

=cut

sub header_pairs { $_[0]->__head->header_pairs }

=head2 body

Returns the body text of the mail.

=cut

sub body {
  my ($self) = @_;
  return defined($self->{body}) ? $self->{body} : '';
}

=head2 body_set

Sets the body text of the mail.

=cut

sub body_set { $_[0]->{body} = $_[1]; $_[0]->body }

=head2 as_string

Returns the mail as a string, reconstructing the headers.

If you've added new headers with C<header_set> that weren't in the original
mail, they'll be added to the end.

=cut

sub as_string {
  my $self = shift;
  return $self->__head->as_string . $self->{mycrlf} . $self->body;
}

package Email::Simple::__Header;

sub new {
  my ($class, $headers, $arg) = @_;

  my $self = {};
  $self->{mycrlf} = $arg->{crlf} || "\n";

  for my $header (@$headers) {
    push @{ $self->{order} }, $header->[0];
    push @{ $self->{head}{ $header->[0] } }, $header->[1];
  }

  $self->{header_names} = { map { lc $_ => $_ } keys %{ $self->{head} } };

  bless $self => $class;
}

# RFC 2822, 3.6:
# ...for the purposes of this standard, header fields SHOULD NOT be reordered
# when a message is transported or transformed.  More importantly, the trace
# header fields and resent header fields MUST NOT be reordered, and SHOULD be
# kept in blocks prepended to the message.

sub as_string {
  my ($self) = @_;

  my $header_str = '';
  my @pairs      = $self->header_pairs;

  while (my ($name, $value) = splice @pairs, 0, 2) {
    $header_str .= $self->_header_as_string($name, $value);
  }

  return $header_str;
}

sub _header_as_string {
  my ($self, $field, $data) = @_;

  # Ignore "empty" headers
  return '' unless defined $data;

  my $string = "$field: $data";

  return (length $string > 78)
    ? $self->_fold($string)
    : ($string . $self->{mycrlf});
}

sub _fold {
  my $self = shift;
  my $line = shift;

  # We know it will not contain any new lines at present
  my $folded = "";
  while ($line) {
    $line =~ s/^\s+//;
    if ($line =~ s/^(.{0,77})(\s|\z)//) {
      $folded .= $1 . $self->{mycrlf};
      $folded .= " " if $line;
    } else {

      # Basically nothing we can do. :(
      $folded .= $line . $self->{mycrlf};
      last;
    }
  }
  return $folded;
}

sub header_names {
  values %{ $_[0]->{header_names} };
}

sub header_pairs {
  my ($self) = @_;

  my @headers;
  my %seen;

  for my $header (@{ $self->{order} }) {
    push @headers, ($header, $self->{head}{$header}[ $seen{$header}++ ]);
  }

  return @headers;
}

sub header {
  my ($self, $field) = @_;
  return
    unless (exists $self->{header_names}->{ lc $field })
    and $field = $self->{header_names}->{ lc $field };

  return wantarray
    ? @{ $self->{head}->{$field} }
    : $self->{head}->{$field}->[0];
}

sub header_set {
  my ($self, $field, @data) = @_;

  # I hate this block. -- rjbs, 2006-10-06
  if ($Email::Simple::GROUCHY) {
    Carp::croak "field name contains illegal characters"
      unless $field =~ /^[\x21-\x39\x3b-\x7e]+$/;
    Carp::carp "field name is not limited to hyphens and alphanumerics"
      unless $field =~ /^[\w-]+$/;
  }

  if (!exists $self->{header_names}->{ lc $field }) {
    $self->{header_names}->{ lc $field } = $field;

    # New fields are added to the end.
    push @{ $self->{order} }, $field;
  } else {
    $field = $self->{header_names}->{ lc $field };
  }

  my @loci =
    grep { lc $self->{order}[$_] eq lc $field } 0 .. $#{ $self->{order} };

  if (@loci > @data) {
    my $overage = @loci - @data;
    splice @{ $self->{order} }, $_, 1 for reverse @loci[ -$overage, $#loci ];
  } elsif (@data > @loci) {
    push @{ $self->{order} }, ($field) x (@data - @loci);
  }

  $self->{head}->{$field} = [@data];
  return wantarray ? @data : $data[0];
}

1;

__END__

=head1 CAVEATS

Email::Simple handles only RFC2822 formatted messages.  This means you
cannot expect it to cope well as the only parser between you and the
outside world, say for example when writing a mail filter for
invocation from a .forward file (for this we recommend you use
L<Email::Filter> anyway).  For more information on this issue please
consult RT issue 2478, http://rt.cpan.org/NoAuth/Bug.html?id=2478 .

=head1 PERL EMAIL PROJECT

This module is maintained by the Perl Email Project

L<http://emailproject.perl.org/wiki/Email::Simple>

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Casey West

Copyright 2003 by Simon Cozens

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
