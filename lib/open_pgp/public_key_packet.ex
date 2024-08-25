defmodule OpenPGP.PublicKeyPacket do
  @moduledoc """
  Represents structured data for Public-Key Packet.

  ---

  ## [RFC4880](https://www.ietf.org/rfc/rfc4880.txt)

  ### 5.5.2.  Public-Key Packet Formats

  There are two versions of key-material packets.  Version 3 packets
  were first generated by PGP 2.6.  Version 4 keys first appeared in
  PGP 5.0 and are the preferred key version for OpenPGP.

  OpenPGP implementations MUST create keys with version 4 format.  V3
  keys are deprecated; an implementation MUST NOT generate a V3 key,
  but MAY accept it.

  A version 3 public key or public-subkey packet contains:

    - A one-octet version number (3).

    - A four-octet number denoting the time that the key was created.

    - A two-octet number denoting the time in days that this key is
      valid.  If this number is zero, then it does not expire.

    - A one-octet number denoting the public-key algorithm of this key.

    - A series of multiprecision integers comprising the key material:

          - a multiprecision integer (MPI) of RSA public modulus n;

          - an MPI of RSA public encryption exponent e.

  V3 keys are deprecated.  They contain three weaknesses.  First, it is
  relatively easy to construct a V3 key that has the same Key ID as any
  other key because the Key ID is simply the low 64 bits of the public
  modulus.  Secondly, because the fingerprint of a V3 key hashes the
  key material, but not its length, there is an increased opportunity
  for fingerprint collisions.  Third, there are weaknesses in the MD5
  hash algorithm that make developers prefer other algorithms.  See
  below for a fuller discussion of Key IDs and fingerprints.

  V2 keys are identical to the deprecated V3 keys except for the
  version number.  An implementation MUST NOT generate them and MAY
  accept or reject them as it sees fit.

  The version 4 format is similar to the version 3 format except for
  the absence of a validity period.  This has been moved to the
  Signature packet.  In addition, fingerprints of version 4 keys are
  calculated differently from version 3 keys, as described in the
  section "Enhanced Key Formats".

  A version 4 packet contains:

    - A one-octet version number (4).

    - A four-octet number denoting the time that the key was created.

    - A one-octet number denoting the public-key algorithm of this key.

    - A series of multiprecision integers comprising the key material.
      This algorithm-specific portion is:

      Algorithm-Specific Fields for RSA public keys:

        - multiprecision integer (MPI) of RSA public modulus n;

        - MPI of RSA public encryption exponent e.

      Algorithm-Specific Fields for DSA public keys:

        - MPI of DSA prime p;

        - MPI of DSA group order q (q is a prime divisor of p-1);

        - MPI of DSA group generator g;

        - MPI of DSA public-key value y (= g**x mod p where x
          is secret).

      Algorithm-Specific Fields for Elgamal public keys:

        - MPI of Elgamal prime p;

        - MPI of Elgamal group generator g;
        - MPI of Elgamal public key value y (= g**x mod p where x
          is secret).
  """

  @behaviour OpenPGP.Packet.Behaviour

  alias OpenPGP.Util

  defstruct [:id, :fingerprint, :version, :created_at, :expires, :algo, :material]

  @type t :: %__MODULE__{
          id: binary(),
          fingerprint: binary(),
          version: 2 | 3 | 4,
          created_at: DateTime.t(),
          expires: nil | non_neg_integer(),
          algo: OpenPGP.Util.public_key_algo_tuple(),
          material: tuple()
        }

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{ version: 2 }), do: throw(:not_implemented)
  def encode(%__MODULE__{ version: 3 }), do: throw(:not_implemented)
  def encode(%__MODULE__{ version: 4 } = input) do
    timestamp = DateTime.to_unix(input.created_at)
    {algo_id, _algo_name} = input.algo
    <<4::8, timestamp::32, algo_id::8>> <> encode_material(algo_id, input.material)
  end


  @doc """
  Decode Public Key Packet given input binary.
  Return structured packet and remaining binary.
  """
  @impl OpenPGP.Packet.Behaviour
  @spec decode(binary()) :: {t(), binary()}
  def decode("" <> _ = input) do
    {version, timestamp, expire, algo, next} =
      case input do
        <<2::8, ts::32, exp::16, algo::8, next::binary>> -> {2, ts, exp, algo, next}
        <<3::8, ts::32, exp::16, algo::8, next::binary>> -> {3, ts, exp, algo, next}
        <<4::8, ts::32, algo::8, next::binary>> -> {4, ts, nil, algo, next}
      end

    {material, next} = decode_material(algo, next)
    {key_id, fingerprint} = build_key_id(input, next)

    created_at = DateTime.from_unix!(timestamp)

    packet = %__MODULE__{
      id: key_id,
      fingerprint: fingerprint,
      version: version,
      created_at: created_at,
      expires: expire,
      algo: Util.public_key_algo_tuple(algo),
      material: material
    }

    {packet, next}
  end

  defp encode_material(algo_id, {mod_n, exp_e}) when algo_id in [1, 2, 3] do
    Util.encode_mpi(mod_n) <> Util.encode_mpi(exp_e)
  end

  # Support only RSA as of version 0.5.x
  defp decode_material(algo, "" <> _ = input) when algo in [1, 2, 3] do
    {mod_n, next} = Util.decode_mpi(input)
    {exp_e, rest} = Util.decode_mpi(next)

    {{mod_n, exp_e}, rest}
  end

  defp build_key_id("" <> _ = input, "" <> _ = next) do
    payload_length = byte_size(input) - byte_size(next)
    <<payload::binary-size(payload_length), _::binary>> = input
    hash_material = <<0x99::8, payload_length::2*8, payload::binary>>
    fingerprint = :crypto.hash(:sha, hash_material)
    <<_::96, id::binary-size(8)>> = fingerprint

    {id, fingerprint}
  end
end
