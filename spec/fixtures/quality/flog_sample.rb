class Simple
  def trivial
    42
  end
end

class Branchy
  def heavy(a, b, c)
    if a && b
      c.each do |item|
        item.tap do |i|
          i.save! if i.valid? && i.fresh?
        end
      end
    else
      raise ArgumentError
    end
  end
end
