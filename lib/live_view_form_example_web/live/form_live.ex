defmodule LiveViewFormExampleWeb.FormLive do
  use LiveViewFormExampleWeb, :live_view

  defmodule Transaction do
    use Ecto.Schema
    import Ecto.Changeset

    embedded_schema do
      field :date, :date
      field :description, :string
      field :amount, Money.Ecto.Type

      embeds_many :receipts, Transaction.Receipt, on_replace: :delete
    end

    def changeset(transaction \\ %__MODULE__{}, params) do
      transaction
      |> cast(params, [:date, :description, :amount])
      |> validate_required([:date, :description, :amount])
      |> cast_embed(:receipts, sort_param: :receipts_sort, drop_param: :receipts_drop)
    end

    defmodule Receipt do
      use Ecto.Schema
      import Ecto.Changeset

      embedded_schema do
        field :number, :string
        field :amount, Money.Ecto.Type
      end

      def changeset(receipt \\ %__MODULE__{}, params) do
        receipt
        |> cast(params, [:number, :amount])
        |> validate_required([:number, :amount])
      end
    end
  end

  def mount(_params, _session, socket) do
    transaction = %Transaction{
      id: Ecto.UUID.generate(),
      date: Date.utc_today(),
      description: "Test transaction",
      amount: Money.new(100_00, "GBP"),
      receipts: [
        %Transaction.Receipt{
          id: Ecto.UUID.generate(),
          number: "1",
          amount: Money.new(10_00, "GBP")
        }
      ]
    }

    socket =
      assign(socket,
        transaction: transaction,
        form: to_form(Transaction.changeset(transaction, %{}))
      )

    {:ok, socket}
  end

  def handle_event("update", %{"transaction" => params}, socket) do
    transaction = socket.assigns.transaction
    changeset = Transaction.changeset(transaction, params)
    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def render(assigns) do
    ~H"""
    <.header class="border-b">Form</.header>

    <.form for={@form} phx-change="update" phx-submit="save" class="space-y-4">
      <div class="flex items-center gap-2">
        <.input field={@form[:date]} type="date" label="Date" />
        <.input field={@form[:description]} type="text" label="Description" />
        <%!-- If I change this to type="number" then the value won’t be seen because %Money{amount: 100_00, currency: "GBP"} is not a number and to_string(money) = "£100.00" --%>
        <%!-- I would want the £ excluded from the input because it gets the way of working with the numeric value --%>
        <%!-- Some kind of protocol like to_string/1 that allows me to define how to convert the value to the input type would be nice --%>
        <.input field={@form[:amount]} type="text" label="Amount" />
      </div>
      <div class="grid grid-cols-[1fr_2fr_auto] gap-2 items-center">
        <.header class="col-span-3 text-lg font-bold">Receipts</.header>
        <.inputs_for :let={receipt} field={@form[:receipts]}>
          <input type="hidden" name={@form.name <> "[receipts_sort][]"} value={receipt.index} />
          <.input field={receipt[:number]} type="text" label="Number" />
          <.input field={receipt[:amount]} type="text" label="Amount" />
          <button
            type="button"
            class="text-red-500"
            name={@form.name <> "[receipts_drop][]"}
            value={receipt.index}
            phx-click={JS.dispatch("change")}
          >
            <.icon name="hero-x-mark" class="relative w-6 h-6 top-2" />
          </button>
        </.inputs_for>
      </div>
      <.button
        type="button"
        data-comment="Generating this name could be easier"
        name={@form.name <> "[receipts_sort][]"}
        value="add"
        phx-click={JS.dispatch("change")}
      >
        Add receipt
      </.button>
      <div>
        <% remaining = calculate_remaining(@form) %> Remaining to allocate:
        <strong class={if(Money.zero?(remaining), do: "text-green-500", else: "text-red-500")}>
          <%= remaining %>
        </strong>
      </div>
      <div>
        Transaction amount: <pre><%= inspect(@form[:amount].value) %></pre>
      </div>
      <div>
        Receipts: <pre class="whitespace-pre-wrap"><%= inspect(@form[:receipts].value) %></pre>
      </div>
    </.form>
    """
  end

  defp calculate_remaining(%Phoenix.HTML.Form{} = form) do
    # Can’t guarantee that this is a Money struct, sometimes it’s a string — "£100.00"
    # amount = form[:amount].value
    amount = parse_amount(form[:amount].value)

    # When I remove the intial receipt, this doesn’t correctly recalculate because there is a changeset indicating the removal that is unaccounted for

    receipts = form[:receipts].value
    # This doesn’t work because sometimes receipts is a list of Changesets
    # receipts_total = receipts |> Enum.reduce(Money.new(0, "GBP"), &Money.add(&2, &1.amount))
    receipts_total = sum_receipts(receipts)
    Money.subtract(amount, receipts_total)
  end

  defp sum_receipts(receipts) do
    receipts
    |> Enum.reduce(Money.new(0, "GBP"), fn receipt, acc ->
      IO.inspect(receipt, label: "receipt", structs: false)
      Money.add(acc, receipt_amount(receipt))
    end)
  end

  defp receipt_amount(%{amount: amount}), do: amount

  # I need to account for a removed receipt (one from the original list, not added through the form, i.e. the first receipt) (otherwise the total is incorrect)
  defp receipt_amount(%Ecto.Changeset{action: :replace}) do
    Money.new(0, "GBP")
  end

  defp receipt_amount(%Ecto.Changeset{} = changeset) do
    case Ecto.Changeset.get_field(changeset, :amount) do
      # This case could be handled with a default value in the struct (but what if I need to set the currency?)
      nil -> Money.new(0, "GBP")
      %Money{} = amount -> amount
    end
  end

  # This happens randomly—I can’t pin it down
  # It happened when I adjusted the overall amount of the transaction
  # It happens fairly reliably if I add a receipt and then remove it without having changed anything else
  defp receipt_amount({_idx, %{"amount" => amount}}) do
    parse_amount(amount)
  end

  defp parse_amount(%Money{} = money), do: money

  # This is needed only in the case where a changeset is deleted (above: {_idx, %{"amount" => ""}})
  defp parse_amount(""), do: Money.new(0, "GBP")

  # Sometimes the money is a string
  defp parse_amount(value) do
    Money.parse!(value)
  end
end
