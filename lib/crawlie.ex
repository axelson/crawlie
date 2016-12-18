defmodule Crawlie do

  alias Experimental.Flow

  alias Crawlie.Options
  alias Crawlie.Page
  alias Crawlie.Stage.UrlManager


  @spec crawl(Stream.t, module, Keyword.t) :: Flow.t
  @doc """
  Crawls the urls provided in `source`, using the `Crawlie.ParserLogic` provided
  in `parser_logic`.

  The `options` are used to tweak the crawler's behaviour. You can use most of
  the options for [HttPoison](https://hexdocs.pm/httpoison/HTTPoison.html#request/5),
  as well as Crawlie specific options.


  ## arguments
  - `source` - a `Stream` or an `Enum` containing the urls to crawl
  - `parser_logic`-  a `Crawlie.ParserLogic` behaviour implementation
  - `options` - options

  ## Crawlie options

  - `:http_client` - module implementing the `Crawlie.HttpClient` behaviour to be
    used to make the requests. If not provided, will default to `Crawlie.HttpClient.HTTPoisonClient`.
  - `:mock_client_fun` - If you're using the `Crawlie.HttpClient.MockClient`, this
    would be the `url -> {:ok, body :: String.t} | {:error, term}` function simulating
    making the requests.
  """
  def crawl(source, parser_logic, options \\ []) do
    options = Options.with_defaults(options)
    client = Keyword.get(options, :http_client)

    # results = source
    #   |> Stream.map(&client.get(&1, options))
    #   |> Stream.map(&elem(&1, 1))
    #   |> Stream.map(&parser_logic.parse("fake_url", &1))
    #   |> Stream.flat_map(&parser_logic.extract_data(&1))

    # {:ok, url_stage} = GenStage.from_enumerable(source)
    {:ok, url_stage} = UrlManager.start_link(source)

    # results = GenStage.stream([url_stage])

    url_stage
      |> Flow.from_stage(options)
      |> Flow.map(fn(%Page{url: url}) ->
        url
      end)
      |> Flow.map(fn url -> {url, elem(client.get(url, options), 1)} end)
      |> Flow.map(fn {url, body} -> {url, parser_logic.parse(url, body)} end)
      |> Flow.flat_map(fn {url, parsed} -> parser_logic.extract_data(url, parsed) end)
  end

end
