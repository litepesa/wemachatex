defmodule WemachatCoreTest do
  use ExUnit.Case
  doctest WemachatCore

  test "greets the world" do
    assert WemachatCore.hello() == :world
  end
end
