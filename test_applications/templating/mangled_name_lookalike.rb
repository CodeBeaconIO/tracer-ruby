# frozen_string_literal: true

# A regular class in a regular .rb file that deliberately defines a method
# whose name matches the shape of an ActionView-compiled template method
# (`_<path-ish>__<digits>_<digits>`). Any method-name-pattern rewrite that
# ignores tp.path could incorrectly trigger here. This file is a .rb, so a
# path-based rewrite would (correctly) leave it alone.
class MangledNameLookalike
  define_method(:_app_views_fake_html_erb__1234567890_42) do
    :ok
  end
end
