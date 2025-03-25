class CannotToS
  def inspect
    raise 'Cannot inspect'
  end

  def to_s
    raise 'Cannot to_s'
  end
end