#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Crypt::OpenSSL::Bignum;
use Crypt::OpenSSL::RSA;
use MIME::Base64;
use WWW::Mechanize;


my $url = 'https://presseportal.zdf.de/start/';
my $url_publickey = 'https://presseportal.zdf.de/start/index.php?eID=FrontendLoginRsaPublicKey';


my $mech = WWW::Mechanize->new ();

my $result = $mech->get ($url);
$result = $mech->get ($url_publickey);

# split the result into modulus and exponent
my ($modulus, $exponent) = ($mech->content() =~ m|([0-9A-F]+):([0-9A-F]+):| );

printf "n: %s, e: %s\n\n", $modulus, $exponent;

my $n = Crypt::OpenSSL::Bignum->new_from_hex($modulus);
my $e = Crypt::OpenSSL::Bignum->new_from_hex($exponent);

my $rsa = Crypt::OpenSSL::RSA->new_key_from_parameters($n, $e);

my $password_rsa = $rsa->encrypt('MySuperPassword');
my $password_rsa_base64 = encode_base64 ($password_rsa);
$password_rsa_base64 =~ s/\n//g;
my $password_rsaauth = 'rsa:' . $password_rsa_base64;

printf "rsauth style password: %s\n", $password_rsaauth;

printf "public key (in PKCS1 format) is: %s\n", $rsa->get_public_key_string();
