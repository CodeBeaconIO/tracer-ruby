class CannotInspect
  def initialize(val)
    @val = val
  end

  def inspect
    raise 'Cannot inspect'
  end

  def to_s
    @val.to_s
  end
end
