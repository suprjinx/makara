require 'spec_helper'

describe Makara::Middleware do

  let(:app){
    lambda{|env|
      proxy.query(env[:query] || 'select * from users')
      [200, {}, ["#{Makara::Context.get_current}-#{Makara::Context.get_previous}"]]
    }
  }

  let(:env){ {} }
  let(:proxy){ FakeProxy.new(config(1,2)) }
  let(:middleware){ described_class.new(app) }

  let(:key){ Makara::Middleware::IDENTIFIER }
  let(:cache_key){ Makara::Middleware::CACHE_IDENTIFIER }

  it 'should set the context before the request' do
    Makara::Context.set_previous 'old'
    Makara::Context.set_current 'old'

    response = middleware.call(env)
    current, prev = context_from(response)

    expect(current).not_to eq('old')
    expect(prev).not_to eq('old')

    expect(current).to eq(Makara::Context.get_current)
    expect(prev).to eq(Makara::Context.get_previous)
  end

  it 'should use the cookie-provided context if present' do
    env['HTTP_COOKIE'] = "#{key}=abcdefg--200; path=/; max-age=5"

    response = middleware.call(env)
    current, prev = context_from(response)

    expect(prev).to eq('abcdefg')
    expect(current).to eq(Makara::Context.get_current)
    expect(current).not_to eq('abcdefg')
  end

  it 'should use the param-provided context if present' do
    env['QUERY_STRING'] = "dog=true&#{key}=abcdefg&cat=false"

    response = middleware.call(env)
    current, prev = context_from(response)

    expect(prev).to eq('abcdefg')
    expect(current).to eq(Makara::Context.get_current)
    expect(current).not_to eq('abcdefg')
  end

  it 'should set the cookie if master is used' do
    env[:query] = 'update users set name = "phil"'

    status, headers, body = middleware.call(env)

    expect(headers['Set-Cookie']).to eq("#{key}=#{Makara::Context.get_current}--200; path=/; max-age=5; HttpOnly")
  end

  it 'should preserve the same context if the previous request was a redirect' do
    env['HTTP_COOKIE'] = "#{key}=abcdefg--301; path=/; max-age=5"

    response    = middleware.call(env)
    curr, prev  = context_from(response)

    expect(curr).to eq('abcdefg')
    expect(prev).to eq('abcdefg')

    env['HTTP_COOKIE'] = response[1]['Set-Cookie']

    response      = middleware.call(env)
    curr2, prev2  = context_from(response)

    expect(prev2).to eq('abcdefg')
    expect(curr2).to eq(Makara::Context.get_current)
  end

  it 'should load a base-64 encoded hash when present'  do
    env['HTTP_COOKIE'] = "#{cache_key}=LS0tCjp0OiB0Cg==; path=/; max-age=5"
    middleware.call(env)
    expect(Thread.current[cache_key]).to be
  end

  it 'stores the hash in a thread local variable'  do
    env['HTTP_COOKIE'] = "#{cache_key}=LS0tCjp0OiB0Cg==; path=/; max-age=5"
    middleware.call(env)
    expect(Thread.current[cache_key]).to eq({t: 't'})
  end

  it 'creates an empty hash in the thread local if the cookie is no present'  do
    middleware.call(env)
    expect(Thread.current[cache_key]).to eq({})
  end

  context 'when the cache is altered during the request' do
    let(:app) {
      lambda{|env|
        Thread.current[cache_key] = {cache_key: 'value'}
        proxy.query(env[:query] || 'select * from users')
        [200, {}, ["#{Makara::Context.get_current}-#{Makara::Context.get_previous}"]]
      }
    }
    it 'should write the cookie-based hash to the response' do
      response = middleware.call(env)
      cookies = response[1]['Set-Cookie'].split("\n")
      expect(cookies[1]).to start_with('_mkra_cache')
    end

    it 'should base-64 encode the cookie-based hash' do
      response = middleware.call(env)
      cookies = response[1]['Set-Cookie'].split("\n")
      value = cookies[1].split("=")[1].split(';')[0]
      expect(Base64.decode64(value)).to be
    end
  end

  context 'when the cache is empty after the request' do
    it 'should not write the cookie-based hash to the response' do
      response = middleware.call(env)
      cookies = response[1]['Set-Cookie']
      expect(cookies).not_to include('_mkra_cache')
    end
  end

  def context_from(response)
    response[2][0].split('-')
  end

end
