defmodule Joken.Config.Test do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias Joken.{Config, CurrentTime.Mock}

  setup do
    {:ok, _pid} = start_supervised(Mock)
    :ok
  end

  describe "Joken.Config.default_claims/1" do
    property "any given issuer will be validated" do
      check all issuer <- binary() do
        iss_claim = Config.default_claims(iss: issuer)["iss"]
        assert iss_claim.validate.(issuer, %{})
      end
    end

    test "generates exp, iss, iat, nbf claims" do
      assert Config.default_claims() |> Map.keys() == ["aud", "exp", "iat", "iss", "jti", "nbf"]
    end

    test "can customize exp duration" do
      Mock.freeze()

      # 1 second
      exp_claim = Config.default_claims(default_exp: 1)["exp"]
      assert exp_claim.generate.() > Joken.current_time()

      # Zero seconds
      exp_claim = Config.default_claims(default_exp: 0)["exp"]
      assert exp_claim.generate.() <= Joken.current_time()
    end

    test "can skip claims" do
      keys = Config.default_claims(skip: [:exp]) |> Map.keys()
      assert keys == ["aud", "iat", "iss", "jti", "nbf"]

      keys = Config.default_claims(skip: [:exp, :iat]) |> Map.keys()
      assert keys == ["aud", "iss", "jti", "nbf"]

      assert Config.default_claims(skip: [:aud, :exp, :iat, :iss, :jti, :nbf]) == %{}
    end

    test "can set a different issuer" do
      assert Config.default_claims(iss: "Custom")["iss"].generate.() == "Custom"
    end

    test "default exp validates properly" do
      Mock.freeze()

      exp_claim = Config.default_claims()["exp"]
      # 1 second expiration
      assert exp_claim.validate.(Joken.current_time() + 1, %{})

      # -1 second expiration (always expired)
      refute exp_claim.validate.(Joken.current_time() - 1, %{})

      # 0 second expiration (always expired)
      refute exp_claim.validate.(Joken.current_time(), %{})
    end

    test "default iss validates properly" do
      exp_claim = Config.default_claims()["iss"]
      assert exp_claim.validate.("Joken", %{})
      refute exp_claim.validate.("Another", %{})
    end

    test "default nbf validates properly" do
      Mock.freeze()
      exp_claim = Config.default_claims()["nbf"]

      # Not before current time
      assert exp_claim.validate.(Joken.current_time(), %{})

      # not before a second ago
      assert exp_claim.validate.(Joken.current_time() - 1, %{})

      # not before a second in the future
      refute exp_claim.validate.(Joken.current_time() + 1, %{})
    end

    test "can switch default jti generation function" do
      jti_claim = Config.default_claims(generate_jti: fn -> "Hi" end)["jti"]

      assert jti_claim.generate.() == "Hi"
    end
  end

  describe "generate_and_sign/verify_and_update" do
    property "should always pass for the same signer" do
      generator =
        StreamData.map_of(
          StreamData.string(:ascii),
          StreamData.one_of([
            StreamData.string(:ascii),
            StreamData.integer(),
            StreamData.boolean(),
            StreamData.map_of(
              StreamData.string(:ascii),
              StreamData.one_of([
                StreamData.string(:ascii),
                StreamData.integer(),
                StreamData.boolean()
              ])
            )
          ])
        )

      defmodule PropertyEncodeDecode do
        use Joken.Config
      end

      check all input_map <- generator do
        {:ok, token} = PropertyEncodeDecode.generate_and_sign(input_map)
        {:ok, claims} = PropertyEncodeDecode.verify_and_validate(token)

        assert_map_contains_other(claims, input_map)
      end
    end
  end

  defp assert_map_contains_other(target, contains_map) do
    contains_map
    |> Enum.each(fn
      {"", _val} ->
        :ok

      {key, value} ->
        result = Map.fetch(target, key)

        case result do
          {:ok, cur_value} ->
            unless value == cur_value do
              raise """
              Value for key #{key} differs. 

              Expected: #{inspect(value)}
              Got:      #{inspect(cur_value)}
              """
            end

          val ->
            raise """
            Expected value differs.

            Got: #{inspect(val)}.
            """
        end
    end)
  end
end
