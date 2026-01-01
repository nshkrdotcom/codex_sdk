# Example: Using the ApplyPatch Hosted Tool
#
# This example demonstrates how to use the ApplyPatch tool to apply
# *** Begin Patch edits to files, including:
# - Creating new files
# - Modifying existing files
# - Deleting files
# - Dry-run validation
# - Approval integration
#
# Run: mix run examples/apply_patch_tool.exs

alias Codex.Tools.ApplyPatchTool

# Create a temporary directory for the example
tmp_dir = Path.join(System.tmp_dir!(), "apply_patch_example_#{:rand.uniform(1_000_000)}")
File.mkdir_p!(tmp_dir)

IO.puts("Working in: #{tmp_dir}\n")

# Clean up on exit
cleanup = fn ->
  File.rm_rf!(tmp_dir)
  IO.puts("\nCleaned up temporary directory")
end

try do
  # Example 1: Create a new file
  IO.puts("=== Example 1: Create a new file ===")

  create_patch = """
  *** Begin Patch
  *** Add File: hello.txt
  +Hello, World!
  +This is a new file
  +Created by ApplyPatch
  *** End Patch
  """

  args = %{"input" => create_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{})

  IO.puts("Result: #{inspect(result)}")
  IO.puts("File contents:")
  IO.puts(File.read!(Path.join(tmp_dir, "hello.txt")))
  IO.puts("")

  # Example 2: Modify an existing file
  IO.puts("=== Example 2: Modify an existing file ===")

  modify_patch = """
  *** Begin Patch
  *** Update File: hello.txt
  @@
   Hello, World!
  -This is a new file
  +This is a modified file
  +With an extra line
   Created by ApplyPatch
  *** End Patch
  """

  args = %{"input" => modify_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{})

  IO.puts("Result: #{inspect(result)}")
  IO.puts("Modified file contents:")
  IO.puts(File.read!(Path.join(tmp_dir, "hello.txt")))
  IO.puts("")

  # Example 3: Dry-run validation
  IO.puts("=== Example 3: Dry-run validation ===")

  dangerous_patch = """
  *** Begin Patch
  *** Add File: dangerous.txt
  +This file would be created
  *** End Patch
  """

  args = %{"input" => dangerous_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})

  IO.puts("Dry run result: #{inspect(result)}")
  IO.puts("File exists? #{File.exists?(Path.join(tmp_dir, "dangerous.txt"))}")
  IO.puts("")

  # Example 4: Approval callback
  IO.puts("=== Example 4: Approval callback ===")

  review_patch = """
  *** Begin Patch
  *** Add File: reviewed.txt
  +This change was reviewed
  *** End Patch
  """

  # Approval that inspects changes
  approval_callback = fn changes, _ctx ->
    IO.puts("Reviewing changes:")

    Enum.each(changes, fn change ->
      IO.puts("  - #{change.kind}: #{change.path} (+#{change.additions}/-#{change.deletions})")
    end)

    # Approve changes
    :ok
  end

  args = %{"input" => review_patch, "base_path" => tmp_dir}
  context = %{metadata: %{approval: approval_callback}}
  {:ok, result} = ApplyPatchTool.invoke(args, context)

  IO.puts("Result: #{inspect(result)}")
  IO.puts("")

  # Example 5: Denied approval
  IO.puts("=== Example 5: Denied approval ===")

  denied_patch = """
  *** Begin Patch
  *** Add File: secret.txt
  +This should not be created
  *** End Patch
  """

  deny_callback = fn _changes, _ctx ->
    {:deny, "Files named 'secret' are not allowed"}
  end

  args = %{"input" => denied_patch, "base_path" => tmp_dir}
  context = %{metadata: %{approval: deny_callback}}
  result = ApplyPatchTool.invoke(args, context)

  IO.puts("Result: #{inspect(result)}")
  IO.puts("File exists? #{File.exists?(Path.join(tmp_dir, "secret.txt"))}")
  IO.puts("")

  # Example 6: Create nested directories
  IO.puts("=== Example 6: Create nested directories ===")

  nested_patch = """
  *** Begin Patch
  *** Add File: src/lib/utils/helper.ex
  +defmodule Helper do
  +  def greet(name) do
  +    "Hello, \#{name}!"
  +  end
  +end
  *** End Patch
  """

  args = %{"input" => nested_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{})

  IO.puts("Result: #{inspect(result)}")
  IO.puts("File contents:")
  IO.puts(File.read!(Path.join(tmp_dir, "src/lib/utils/helper.ex")))
  IO.puts("")

  # Example 7: Delete a file
  IO.puts("=== Example 7: Delete a file ===")

  # First list files
  IO.puts("Files before delete:")

  Path.wildcard(Path.join(tmp_dir, "**/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.each(&IO.puts("  #{Path.relative_to(&1, tmp_dir)}"))

  delete_patch = """
  *** Begin Patch
  *** Delete File: reviewed.txt
  *** End Patch
  """

  args = %{"input" => delete_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{})

  IO.puts("\nResult: #{inspect(result)}")
  IO.puts("File exists? #{File.exists?(Path.join(tmp_dir, "reviewed.txt"))}")
  IO.puts("")

  # Example 8: Multiple file changes
  IO.puts("=== Example 8: Multiple file changes ===")

  multi_patch = """
  *** Begin Patch
  *** Add File: file1.txt
  +File 1 content
  *** Add File: file2.txt
  +File 2 content
  *** Add File: file3.txt
  +File 3 content
  *** End Patch
  """

  args = %{"input" => multi_patch, "base_path" => tmp_dir}
  {:ok, result} = ApplyPatchTool.invoke(args, %{})

  IO.puts("Result: #{inspect(result)}")
  IO.puts("Files created: #{result["applied"]}")
  IO.puts("")

  # Final state
  IO.puts("=== Final directory state ===")

  Path.wildcard(Path.join(tmp_dir, "**/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.each(&IO.puts("  #{Path.relative_to(&1, tmp_dir)}"))

  IO.puts("\nAll examples completed successfully!")
after
  cleanup.()
end
