defmodule LiveViewFormExample.Repo do
  use Ecto.Repo,
    otp_app: :live_view_form_example,
    adapter: Ecto.Adapters.Postgres
end
