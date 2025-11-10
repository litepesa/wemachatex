defmodule WemachatCore.Services.MpesaClient do
  @moduledoc """
  M-Pesa Daraja API client for STK Push payments.
  Supports:
  1. One-time KES 99 activation payment
  2. Wallet top-up transactions
  """

  require Logger

  @base_url_sandbox "https://sandbox.safaricom.co.ke"
  @base_url_production "https://api.safaricom.co.ke"

  @auth_url "/oauth/v1/generate?grant_type=client_credentials"
  @stk_push_url "/mpesa/stkpush/v1/processrequest"
  @stk_query_url "/mpesa/stkpushquery/v1/query"

  defmodule TokenResponse do
    @moduledoc false
    defstruct [:access_token, :expires_in]
  end

  defmodule STKPushRequest do
    @moduledoc false
    defstruct [
      :BusinessShortCode,
      :Password,
      :Timestamp,
      :TransactionType,
      :Amount,
      :PartyA,
      :PartyB,
      :PhoneNumber,
      :CallBackURL,
      :AccountReference,
      :TransactionDesc
    ]
  end

  defmodule STKPushResponse do
    @moduledoc false
    defstruct [
      :MerchantRequestID,
      :CheckoutRequestID,
      :ResponseCode,
      :ResponseDescription,
      :CustomerMessage
    ]
  end

  defmodule STKQueryRequest do
    @moduledoc false
    defstruct [:BusinessShortCode, :Password, :Timestamp, :CheckoutRequestID]
  end

  defmodule STKQueryResponse do
    @moduledoc false
    defstruct [:ResultCode, :ResultDesc, :ResponseCode, :ResponseDescription]
  end

  defmodule CallbackData do
    @moduledoc false
    defstruct [:Body]

    defmodule Body do
      @moduledoc false
      defstruct [:stkCallback]

      defmodule STKCallback do
        @moduledoc false
        defstruct [
          :MerchantRequestID,
          :CheckoutRequestID,
          :ResultCode,
          :ResultDesc,
          :CallbackMetadata
        ]

        defmodule CallbackMetadata do
          @moduledoc false
          defstruct [:Item]
        end
      end
    end
  end

  @doc """
  Get OAuth access token from M-Pesa API.
  """
  def get_access_token do
    consumer_key = get_config(:consumer_key)
    consumer_secret = get_config(:consumer_secret)
    base_url = get_base_url()

    auth_string = Base.encode64("#{consumer_key}:#{consumer_secret}")

    headers = [
      {"Authorization", "Basic #{auth_string}"},
      {"Content-Type", "application/json"}
    ]

    url = "#{base_url}#{@auth_url}"

    case HTTPoison.get(url, headers) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"access_token" => token, "expires_in" => expires_in}} ->
            {:ok, %{access_token: token, expires_in: expires_in}}

          {:error, reason} ->
            Logger.error("Failed to parse M-Pesa token response: #{inspect(reason)}")
            {:error, :parse_error}
        end

      {:ok, %{status_code: status_code, body: body}} ->
        Logger.error("M-Pesa token request failed: #{status_code} - #{body}")
        {:error, :auth_failed}

      {:error, %{reason: reason}} ->
        Logger.error("M-Pesa token request error: #{inspect(reason)}")
        {:error, :network_error}
    end
  end

  @doc """
  Initiate STK Push payment request.

  ## Parameters
  - phone_number: User's M-Pesa phone number (format: 254XXXXXXXXX)
  - amount: Payment amount in KES
  - account_reference: Reference for the transaction (e.g., "WEMA_USER123")
  - transaction_desc: Description (e.g., "WemaChat Activation Fee")
  """
  def initiate_stk_push(phone_number, amount, account_reference, transaction_desc) do
    with {:ok, token} <- get_access_token(),
         {:ok, password, timestamp} <- generate_password() do
      shortcode = get_config(:business_shortcode)
      callback_url = get_config(:callback_url)
      base_url = get_base_url()

      request_body = %{
        "BusinessShortCode" => shortcode,
        "Password" => password,
        "Timestamp" => timestamp,
        "TransactionType" => "CustomerPayBillOnline",
        "Amount" => amount,
        "PartyA" => phone_number,
        "PartyB" => shortcode,
        "PhoneNumber" => phone_number,
        "CallBackURL" => callback_url,
        "AccountReference" => account_reference,
        "TransactionDesc" => transaction_desc
      }

      headers = [
        {"Authorization", "Bearer #{token.access_token}"},
        {"Content-Type", "application/json"}
      ]

      url = "#{base_url}#{@stk_push_url}"

      case HTTPoison.post(url, Jason.encode!(request_body), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} ->
              {:ok,
               %{
                 merchant_request_id: response["MerchantRequestID"],
                 checkout_request_id: response["CheckoutRequestID"],
                 response_code: response["ResponseCode"],
                 response_description: response["ResponseDescription"],
                 customer_message: response["CustomerMessage"]
               }}

            {:error, reason} ->
              Logger.error("Failed to parse STK Push response: #{inspect(reason)}")
              {:error, :parse_error}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("STK Push request failed: #{status_code} - #{body}")
          {:error, :stk_push_failed}

        {:error, %{reason: reason}} ->
          Logger.error("STK Push request error: #{inspect(reason)}")
          {:error, :network_error}
      end
    end
  end

  @doc """
  Query the status of an STK Push transaction.

  ## Parameters
  - checkout_request_id: The CheckoutRequestID from STK Push response
  """
  def query_stk_push_status(checkout_request_id) do
    with {:ok, token} <- get_access_token(),
         {:ok, password, timestamp} <- generate_password() do
      shortcode = get_config(:business_shortcode)
      base_url = get_base_url()

      request_body = %{
        "BusinessShortCode" => shortcode,
        "Password" => password,
        "Timestamp" => timestamp,
        "CheckoutRequestID" => checkout_request_id
      }

      headers = [
        {"Authorization", "Bearer #{token.access_token}"},
        {"Content-Type", "application/json"}
      ]

      url = "#{base_url}#{@stk_query_url}"

      case HTTPoison.post(url, Jason.encode!(request_body), headers) do
        {:ok, %{status_code: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, response} ->
              {:ok,
               %{
                 result_code: response["ResultCode"],
                 result_desc: response["ResultDesc"],
                 response_code: response["ResponseCode"],
                 response_description: response["ResponseDescription"]
               }}

            {:error, reason} ->
              Logger.error("Failed to parse STK Query response: #{inspect(reason)}")
              {:error, :parse_error}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("STK Query request failed: #{status_code} - #{body}")
          {:error, :query_failed}

        {:error, %{reason: reason}} ->
          Logger.error("STK Query request error: #{inspect(reason)}")
          {:error, :network_error}
      end
    end
  end

  @doc """
  Parse M-Pesa callback data from webhook.

  Returns transaction details including:
  - checkout_request_id
  - result_code (0 = success)
  - result_desc
  - amount
  - mpesa_receipt_number
  - phone_number
  - transaction_date
  """
  def parse_callback_data(callback_body) when is_map(callback_body) do
    try do
      stk_callback = get_in(callback_body, ["Body", "stkCallback"])

      if is_nil(stk_callback) do
        {:error, :invalid_callback_format}
      else
        checkout_request_id = stk_callback["CheckoutRequestID"]
        result_code = stk_callback["ResultCode"]
        result_desc = stk_callback["ResultDesc"]

        # Parse callback metadata items
        metadata = parse_callback_metadata(stk_callback["CallbackMetadata"])

        {:ok,
         %{
           checkout_request_id: checkout_request_id,
           result_code: result_code,
           result_desc: result_desc,
           amount: metadata[:amount],
           mpesa_receipt_number: metadata[:mpesa_receipt_number],
           phone_number: metadata[:phone_number],
           transaction_date: metadata[:transaction_date]
         }}
      end
    rescue
      error ->
        Logger.error("Failed to parse callback data: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  def parse_callback_data(callback_string) when is_binary(callback_string) do
    case Jason.decode(callback_string) do
      {:ok, callback_map} -> parse_callback_data(callback_map)
      {:error, reason} -> {:error, {:json_decode_error, reason}}
    end
  end

  # Private Functions

  defp parse_callback_metadata(nil), do: %{}

  defp parse_callback_metadata(%{"Item" => items}) when is_list(items) do
    Enum.reduce(items, %{}, fn item, acc ->
      case item do
        %{"Name" => "Amount", "Value" => value} ->
          Map.put(acc, :amount, value)

        %{"Name" => "MpesaReceiptNumber", "Value" => value} ->
          Map.put(acc, :mpesa_receipt_number, value)

        %{"Name" => "PhoneNumber", "Value" => value} ->
          Map.put(acc, :phone_number, to_string(value))

        %{"Name" => "TransactionDate", "Value" => value} ->
          Map.put(acc, :transaction_date, parse_transaction_date(value))

        _ ->
          acc
      end
    end)
  end

  defp parse_callback_metadata(_), do: %{}

  defp parse_transaction_date(date_value) when is_integer(date_value) do
    # M-Pesa date format: 20240315143022 (YYYYMMDDHHmmss)
    date_string = to_string(date_value)
    parse_transaction_date(date_string)
  end

  defp parse_transaction_date(date_string) when is_binary(date_string) do
    # Format: YYYYMMDDHHmmss
    case DateTime.from_iso8601("#{String.slice(date_string, 0..7)}T#{String.slice(date_string, 8..13)}Z") do
      {:ok, datetime, _} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_transaction_date(_), do: nil

  defp generate_password do
    shortcode = get_config(:business_shortcode)
    passkey = get_config(:passkey)
    timestamp = generate_timestamp()

    password = Base.encode64("#{shortcode}#{passkey}#{timestamp}")

    {:ok, password, timestamp}
  end

  defp generate_timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp get_base_url do
    case get_config(:environment) do
      "production" -> @base_url_production
      _ -> @base_url_sandbox
    end
  end

  defp get_config(key) do
    Application.get_env(:wemachat_core, :mpesa)[key]
  end
end
