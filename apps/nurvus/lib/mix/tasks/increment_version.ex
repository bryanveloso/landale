defmodule Mix.Tasks.IncrementVersion do
  @moduledoc """
  Increments the release version in mix.exs using CalVer format with letter suffixes.

  This prevents Burrito from using cached binaries when code changes.
  Format: YYYY.MM.DD{letter} (e.g., 2025.07.17a, 2025.07.17b, etc.)

  Only the release version is updated - the project version stays at 0.0.0
  since it's not meaningful for standalone binaries.

  ## Usage

      mix increment_version

  """

  use Mix.Task

  @shortdoc "Increments version in CalVer format for Burrito builds"

  def run(_args) do
    mix_exs_path = "mix.exs"

    unless File.exists?(mix_exs_path) do
      Mix.shell().error("mix.exs not found in current directory")
      System.halt(1)
    end

    current_version = get_current_version(mix_exs_path)
    next_version = calculate_next_version(current_version)

    if current_version == next_version do
      Mix.shell().info("✅ Version already current: #{current_version}")
    else
      update_mix_versions(mix_exs_path, next_version)
      Mix.shell().info("📈 #{current_version} → #{next_version}")
      Mix.shell().info("✅ Updated release version to #{next_version}")
      Mix.shell().info("🎯 Ready for Burrito build - cache issue prevented!")
    end
  end

  defp get_current_version(mix_exs_path) do
    content = File.read!(mix_exs_path)

    # Get release version (which Burrito uses for caching)
    case Regex.run(~r/nurvus:\s*\[\s*version:\s*"([^"]+)"/, content) do
      [_, version] ->
        version

      nil ->
        Mix.shell().error("Could not find release version in mix.exs")
        System.halt(1)
    end
  end

  defp calculate_next_version(current_version) do
    todays_base = get_todays_calver()

    case parse_calver_with_letter(current_version) do
      {:ok, ^todays_base, letter} ->
        # Same day, increment letter
        next_letter = get_next_letter(letter)
        "#{todays_base}#{next_letter}"

      {:ok, _different_base, _letter} ->
        # Different day, start fresh with 'a'
        "#{todays_base}a"

      :error ->
        # Not in CalVer format, start fresh with today's date
        "#{todays_base}a"
    end
  end

  defp get_todays_calver do
    {{year, month, day}, _time} = :calendar.local_time()
    month_str = String.pad_leading("#{month}", 2, "0")
    day_str = String.pad_leading("#{day}", 2, "0")
    "#{year}.#{month_str}.#{day_str}"
  end

  defp parse_calver_with_letter(version) do
    case Regex.run(~r/^(\d{4}\.\d{2}\.\d{2})([a-z]?)$/, version) do
      [_, base, letter] -> {:ok, base, letter}
      nil -> :error
    end
  end

  defp get_next_letter(""), do: "a"

  defp get_next_letter(letter) when is_binary(letter) do
    [char_code] = String.to_charlist(letter)

    if char_code >= ?z do
      Mix.shell().error("Cannot increment beyond letter z")
      System.halt(1)
    end

    <<char_code + 1>>
  end

  defp update_mix_versions(mix_exs_path, new_version) do
    content = File.read!(mix_exs_path)

    # Keep project version as SemVer for Mix compatibility
    # Only update release version (which Burrito uses for caching)
    content =
      Regex.replace(
        ~r/(nurvus:\s*\[\s*version:\s*)"[^"]+"/,
        content,
        "\\1\"#{new_version}\""
      )

    File.write!(mix_exs_path, content)
  end
end
