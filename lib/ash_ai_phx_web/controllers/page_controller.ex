defmodule AshAiPhxWeb.PageController do
  use AshAiPhxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
