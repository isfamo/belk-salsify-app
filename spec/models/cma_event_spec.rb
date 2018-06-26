describe CMAEvent, type: :model do
  context '::new_from_cma_row(rows)' do
    before(:each) do
      @args = CMA_FEED_ROW.dup.symbolize_keys!
    end

    it 'should create a valid row - valid date' do
      @row = CSV::Row.new(@args.keys, @args.values)
      event = CMAEvent.new_from_cma_row(@row)

      expect(event).to be_kind_of(CMAEvent)
      expect(event.start_date).to eq(DateTime.new(2016,9,9,0,0).change(offset: offset))
      expect(event.end_date).to eq(DateTime.new(2016,9,10,23,59).change(offset: offset))
    end

    it 'should create a valid row - missing time' do
      @args.except!(:starttime, :endtime)
      @row = CSV::Row.new(@args.keys, @args.values)
      event = CMAEvent.new_from_cma_row(@row)

      expect(event).to be_kind_of(CMAEvent)
      expect(event.start_date).to eq(DateTime.new(2016,9,9,0,0).change(offset: offset))
      expect(event.end_date).to eq(DateTime.new(2016,9,10,0,0).change(offset: offset))
    end

    it 'should have an error for invalid start_date' do
      @args[:startdate] = "asdasda"
      @row = CSV::Row.new(@args.keys, @args.values)

      obj = CMAEvent.new_from_cma_row(@row)
      expect(obj.errors[:date]).to be_present
    end

    it 'should have an error for invalid end_date' do
      @args[:enddate] = "asdasda"
      @row = CSV::Row.new(@args.keys, @args.values)

      obj = CMAEvent.new_from_cma_row(@row)
      expect(obj.errors[:date]).to be_present
    end
  end

  context '#active_today_and_in_future' do
    before(:each) do
      @ev1 = FactoryGirl.create(:cma_event)
      @ev2 = FactoryGirl.create(:cma_event)
    end

    it 'should not return expired events' do
      @ev1.update(start_date: 15.days.ago, # very Old
                  end_date: 10.days.ago)
      @ev2.update(start_date: 15.days.ago, # just expired
                  end_date: DateTime.strptime("#{yesterday} #{beginning_of_day}
                   #{offset}", strp_format) - 1.seconds)
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code))).to eq([])
    end

    it 'should not return future events' do
      @ev1.update(start_date: 10.days.from_now, # future
                  end_date: 15.days.from_now)
      @ev2.update(start_date: DateTime.strptime("#{today} #{end_of_day}
                   #{offset}", strp_format) + 1.second, # nearly future
                  end_date: 15.days.from_now)
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).to_a).to eq([@ev1,@ev2])
    end

    it 'should return active events with both margins inside and outside the interval' do
      @ev1.update(start_date: 15.days.ago, # Wrapping the interval
                  end_date: 15.days.from_now)
      @ev2.update(start_date:DateTime.strptime("#{today} #{beginning_of_day}
                   #{offset}", strp_format), # In the interval
                  end_date: DateTime.strptime("#{today} #{end_of_day}
                   #{offset}", strp_format))
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).to_a).to eq([@ev1,@ev2])
    end

    it 'should return active events with one margin inside the interval' do
      @ev1.update(start_date: 15.days.ago, # End date in interval
                  end_date: DateTime.strptime("#{today} #{end_of_day}
                   #{offset}", strp_format))
      @ev2.update(start_date: DateTime.strptime("#{yesterday} #{beginning_of_day}
                   #{offset}", strp_format), # Start date in interval
                  end_date: 15.days.from_now)
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).to_a).to eq([@ev1,@ev2])
    end

    it 'should return expired events with both margins inside the interval' do
      @ev1.update(start_date: DateTime.strptime("#{yesterday} #{beginning_of_day}
                   #{offset}", strp_format), # In the interval
                  end_date: DateTime.strptime("#{yesterday} #{end_of_day}
                   #{offset}", strp_format))
      @ev2.destroy
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).to_a).to eq([@ev1])
    end

    it 'should return expired events with one margin inside the interval' do
      @ev1.update(start_date: 15.days.ago, # End date in interval
                  end_date: DateTime.strptime("#{yesterday} #{beginning_of_day}
                   #{offset}", strp_format))
      @ev2.update(start_date: 15.days.ago, # End date in interval
                  end_date: DateTime.strptime("#{yesterday} #{end_of_day}
                   #{offset}", strp_format))
      expect(CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).to_a).to eq([@ev1,@ev2])
    end
  end

  context '#group_by' do
    before(:each) do
      @ev1 = FactoryGirl.create(:cma_event, start_date: 10.days.ago, end_date: 10.days.from_now, sku_code: "SAMESKUCODE")
      @ev2 = FactoryGirl.create(:cma_event, start_date: 10.days.ago, end_date: 10.days.from_now, sku_code: "SAMESKUCODE")
    end

    it 'should group the products correctly' do
      grouped = CMAEvent.active_today_and_in_future(Date.today, CMAEvent.all.map(&:sku_code)).group_by(&:sku_code)
      expect(grouped[@ev1.sku_code].count).to eq(2)
    end
  end

  context '#validates_uniqueness_of' do
    it 'should raise an exception if we create two instances with same details' do
      FactoryGirl.create(:cma_event, adevent: "AAA", event_id: "BBB", sku_code: "aaa")
      expect {
        FactoryGirl.create(:cma_event, adevent: "AAA", event_id: "BBB", sku_code: "aaa")
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'should allow two different objects with different PK - sku+event+adevent' do
      FactoryGirl.create(:cma_event)
      FactoryGirl.create(:cma_event)
    end
  end

  context '#ended_on?' do
    it 'should return true if the event started 10 days ago but ended yesterday' do
      event = FactoryGirl.create(:cma_event, start_date: 10.days.ago,
        end_date: DateTime.strptime("#{yesterday} #{end_of_day} #{offset}", strp_format))
      expect(event.ended_on?).to be(true)
    end

    it 'should return true if the event started yesterday morning and ended yesterday evening' do
      event = FactoryGirl.create(:cma_event,
        start_date: DateTime.strptime("#{yesterday} #{beginning_of_day} #{offset}", strp_format),
        end_date: DateTime.strptime("#{yesterday} #{end_of_day} #{offset}", strp_format))
      expect(event.ended_on?).to be(true)
    end

    it 'should return false if event is still active' do
      event = FactoryGirl.create(:cma_event, start_date: 10.days.ago, end_date: 10.days.from_now)
      expect(event.ended_on?).to be(false)
    end

    it 'should return false if event has expired more than 1 day ago' do
      event = FactoryGirl.create(:cma_event, start_date: 10.days.ago, end_date: 9.days.ago)
      expect(event.ended_on?).to be(false)
    end

    it 'should return false if event is in the future' do
      event = FactoryGirl.create(:cma_event, start_date: 9.days.from_now, end_date: 10.days.from_now)
      expect(event.ended_on?).to be(false)
    end
  end
end
