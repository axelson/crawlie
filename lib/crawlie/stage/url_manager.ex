defmodule Crawlie.Stage.UrlManager do
  alias Experimental.GenStage
  alias Crawlie.Page
  alias Heap
  alias __MODULE__, as: This

  use GenStage

  defmodule State do
    @type t :: %State{
      initial: Enum.t, # pages provided by the user
      discovered: Heap.t, # pages discovered while crawling
      visited: Map.t, # url -> retry count
      options: Keyword.t
    }

    @enforce_keys [:initial, :discovered, :visited, :options]
    defstruct [
      :initial,
      :discovered,
      :visited,
      :options,
    ]

    @spec new(Enum.t, Keyword.t) :: State.t
    def new(initial_pages, options \\ []) do
      %State{
        initial: initial_pages,
        discovered: Heap.max(),
        visited: %{},
        options: options,
      }
    end


    @spec take_pages(State.t, integer) :: {State.t, [Page.t]}
    def take_pages(%State{} = state, count) do
      _take_pages(state, count, [])
    end


    defp _take_pages(state, count, acc) when count <= 0, do: {state, acc}
    defp _take_pages(state, count, acc) do
      {state, page} = cond do
        !Heap.empty?(state.discovered) ->
          discovered = state.discovered
          page = Heap.root(discovered)
          {%State{state | discovered: Heap.pop(discovered)}, page}
        !Enum.empty?(state.initial) ->
          initial = state.initial
          [page] = Enum.take(initial, 1)
          {%State{state | initial: Enum.drop(initial, 1)}, page}
        true -> {state, nil}
      end

      # TODO adding the pages to visited.

      case page do
        nil -> {state, acc}
        page -> _take_pages(state, count - 1, [page | acc])
      end
    end

  end


  def start_link(urls, crawlie_options \\ []) when is_list(crawlie_options) do
    pages = Stream.map(urls, &Page.new(&1))
    init_args = %{
      pages: pages,
      crawlie_options: crawlie_options,
    }
    GenStage.start_link(This, init_args)
  end

  #===========================================================================
  # GenStage callbacks
  #===========================================================================

  def init(%{pages: pages, crawlie_options: opts}) do
    {:producer, State.new(pages, opts)}
  end


  def handle_demand(demand, %State{} = state) do
    {new_state, pages} = State.take_pages(state, demand)
    # FIXME smarter handling of when the manager runs out of items

    case Enum.count(pages) do
      ^demand ->
        {:noreply, pages, new_state}
      smaller when smaller < demand ->
        shutdown_gracefully_after_timeout()
        {:noreply, pages, new_state}
    end
  end


  #===========================================================================
  # Helper functions
  #===========================================================================

  def shutdown_gracefully_after_timeout(timeout \\ 10) do
    :timer.apply_after(timeout, This, :shutdown_gracefully, [self()])
  end

  def shutdown_gracefully(pid), do: GenStage.async_notify(pid, {:producer, :done})

end
